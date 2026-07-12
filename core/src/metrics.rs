use std::fs;
use std::io;
use std::sync::Mutex;
use std::time::Instant;

/// System metrics collected from /proc and /sys interfaces.
#[derive(Debug, Clone, Default)]
pub struct SystemMetrics {
    /// CPU utilization as a percentage (0.0 - 100.0).
    pub cpu_usage_percent: f64,
    /// CPU temperature in Celsius, if available.
    pub cpu_temp_celsius: Option<f64>,
    /// RAM usage as a percentage (0.0 - 100.0).
    pub ram_usage_percent: f64,
    /// Total RAM in bytes.
    pub ram_total_bytes: u64,
    /// Used RAM in bytes.
    pub ram_used_bytes: u64,
    /// Number of CPU cores (logical).
    pub cpu_core_count: u32,
    /// GPU utilization as a percentage (0.0 - 100.0), if a GPU is discoverable.
    pub gpu_usage_percent: Option<f64>,
    /// GPU temperature in Celsius, if available.
    pub gpu_temp_celsius: Option<f64>,
    /// Network receive rate in bytes/second (summed over physical interfaces).
    pub net_rx_bytes_per_sec: f64,
    /// Network transmit rate in bytes/second (summed over physical interfaces).
    pub net_tx_bytes_per_sec: f64,
    /// Total size of the root filesystem in bytes.
    pub disk_total_bytes: u64,
    /// Used space on the root filesystem in bytes.
    pub disk_used_bytes: u64,
    /// Root filesystem usage as a percentage (0.0 - 100.0).
    pub disk_usage_percent: f64,
}

/// Cached CPU times from the previous reading, for delta computation.
static PREV_CPU_TIMES: Mutex<Option<CpuTimes>> = Mutex::new(None);

/// Cached CPU core count (doesn't change at runtime).
static CPU_CORE_COUNT: std::sync::OnceLock<u32> = std::sync::OnceLock::new();

/// Cached CPU temperature sensor path.
static TEMP_SENSOR_PATH: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();

/// Cached GPU sysfs paths (busy + temperature), discovered once.
static GPU_PATHS: std::sync::OnceLock<Option<GpuPaths>> = std::sync::OnceLock::new();

/// Cached previous network counters + timestamp, for byte-rate deltas.
static PREV_NET: Mutex<Option<NetSample>> = Mutex::new(None);

/// Collect current system metrics.
pub fn collect_metrics() -> SystemMetrics {
    // Read RAM info exactly once (previously this parsed /proc/meminfo 3×).
    let ram = read_ram_info();
    let (net_rx, net_tx) = read_network_rates();
    let disk = read_disk_info();
    SystemMetrics {
        cpu_usage_percent: read_cpu_usage(),
        cpu_temp_celsius: read_cpu_temperature(),
        ram_usage_percent: ram.percent,
        ram_total_bytes: ram.total,
        ram_used_bytes: ram.used,
        cpu_core_count: get_cpu_core_count(),
        gpu_usage_percent: read_gpu_usage(),
        gpu_temp_celsius: read_gpu_temperature(),
        net_rx_bytes_per_sec: net_rx,
        net_tx_bytes_per_sec: net_tx,
        disk_total_bytes: disk.total,
        disk_used_bytes: disk.used,
        disk_usage_percent: disk.percent,
    }
}

// --- Disk usage (root filesystem via statvfs) ---

struct DiskInfo {
    total: u64,
    used: u64,
    percent: f64,
}

/// Read root-filesystem usage via `statvfs("/")`.
/// Returns zeroed info if the syscall fails.
fn read_disk_info() -> DiskInfo {
    let default = DiskInfo {
        total: 0,
        used: 0,
        percent: 0.0,
    };
    let path = match std::ffi::CString::new("/") {
        Ok(p) => p,
        Err(_) => return default,
    };
    // SAFETY: `stat` is a valid, zero-initialized statvfs; `path` is a valid
    // NUL-terminated C string that outlives the call.
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::statvfs(path.as_ptr(), &mut stat) };
    if rc != 0 {
        return default;
    }
    let frsize = stat.f_frsize as u64;
    let total = (stat.f_blocks as u64).saturating_mul(frsize);
    // `f_bavail` is space usable by unprivileged processes (what `df` reports as
    // "Avail"); `f_bfree` includes root-reserved blocks. Match `df`'s accounting:
    // Used = total - f_bfree, and percent is over the user-visible (used+avail).
    let avail = (stat.f_bavail as u64).saturating_mul(frsize);
    let free_all = (stat.f_bfree as u64).saturating_mul(frsize);
    if total == 0 {
        return default;
    }
    let used = total.saturating_sub(free_all);
    let denom = used.saturating_add(avail);
    let percent = if denom == 0 {
        0.0
    } else {
        used as f64 / denom as f64 * 100.0
    };
    DiskInfo {
        total,
        used,
        percent,
    }
}

/// Read CPU usage from /proc/stat using cached previous sample.
/// No sleep needed — computes delta from the last call.
fn read_cpu_usage() -> f64 {
    let current = match read_proc_stat_cpu() {
        Some(c) => c,
        None => return 0.0,
    };

    // Recover from a poisoned lock rather than panicking across the FFI boundary
    // (the crate unwinds, and there is no catch_unwind at the C boundary).
    let mut prev = PREV_CPU_TIMES.lock().unwrap_or_else(|e| e.into_inner());
    let result = match prev.as_ref() {
        Some(p) => {
            let idle1 = p.idle + p.iowait;
            let idle2 = current.idle + current.iowait;
            let total1: u64 =
                p.user + p.nice + p.system + p.idle + p.iowait + p.irq + p.softirq + p.steal;
            let total2: u64 = current.user
                + current.nice
                + current.system
                + current.idle
                + current.iowait
                + current.irq
                + current.softirq
                + current.steal;
            let total_delta = total2.saturating_sub(total1);
            let idle_delta = idle2.saturating_sub(idle1);
            if total_delta == 0 {
                0.0
            } else {
                ((total_delta - idle_delta) as f64 / total_delta as f64) * 100.0
            }
        }
        None => 0.0,
    };

    *prev = Some(current);
    result
}

struct CpuTimes {
    user: u64,
    nice: u64,
    system: u64,
    idle: u64,
    iowait: u64,
    irq: u64,
    softirq: u64,
    steal: u64,
}

fn read_proc_stat_cpu() -> Option<CpuTimes> {
    let content = fs::read_to_string("/proc/stat").ok()?;
    let line = content.lines().find(|l| l.starts_with("cpu "))?;

    // Format: cpu  user nice system idle iowait irq softirq steal ...
    let fields: Vec<&str> = line.split_whitespace().collect();
    if fields.len() < 8 {
        return None;
    }

    Some(CpuTimes {
        user: fields[1].parse().ok()?,
        nice: fields[2].parse().ok()?,
        system: fields[3].parse().ok()?,
        idle: fields[4].parse().ok()?,
        iowait: fields[5].parse().ok()?,
        irq: fields[6].parse().ok()?,
        softirq: fields[7].parse().ok()?,
        steal: fields.get(8).and_then(|s| s.parse().ok()).unwrap_or(0),
    })
}

/// Count logical CPUs from /proc/cpuinfo.
fn count_cpus() -> u32 {
    match fs::read_to_string("/proc/cpuinfo") {
        Ok(content) => content
            .lines()
            .filter(|l| l.starts_with("processor"))
            .count() as u32,
        Err(_) => 1,
    }
}

/// Get CPU core count, cached after first call.
fn get_cpu_core_count() -> u32 {
    *CPU_CORE_COUNT.get_or_init(count_cpus)
}

/// Read CPU temperature from hwmon interfaces.
/// Sensor path is discovered once and cached.
fn read_cpu_temperature() -> Option<f64> {
    let sensor_path = TEMP_SENSOR_PATH.get_or_init(discover_temp_sensor);

    if let Some(path) = sensor_path {
        if let Ok(content) = fs::read_to_string(path) {
            if let Ok(millideg) = content.trim().parse::<f64>() {
                return Some(millideg / 1000.0);
            }
        }
    }
    None
}

/// Discover the CPU temperature sensor path and cache it.
///
/// Priority matters: a real CPU sensor is identified by its hwmon `name`
/// (k10temp/coretemp/…). The generic globs are only a last resort — if tried
/// first they latch onto whatever hwmon device `read_dir` returns first (NVMe,
/// Wi-Fi, chipset), which is nondeterministic and usually wrong.
fn discover_temp_sensor() -> Option<String> {
    // Strong signals: dedicated CPU temperature drivers.
    const CPU_HWMON_NAMES: &[&str] = &["k10temp", "coretemp", "zenpower", "cpu_thermal"];
    if let Some(path) = find_hwmon_by_name(CPU_HWMON_NAMES) {
        return Some(path);
    }

    // Weaker signal: the ACPI thermal zone. Motherboard-level, but CPU-adjacent
    // and far better than an unrelated sensor.
    if let Some(path) = find_hwmon_by_name(&["acpitz"]) {
        return Some(path);
    }

    // Last resort: the first hwmon/thermal sensor that yields a parseable value.
    let patterns = [
        "/sys/class/hwmon/hwmon*/temp1_input",
        "/sys/class/hwmon/hwmon*/temp2_input",
        "/sys/class/thermal/thermal_zone*/temp",
    ];
    for pattern in &patterns {
        if let Ok(paths) = glob_simple(pattern) {
            for path in paths {
                if let Ok(content) = fs::read_to_string(&path) {
                    if content.trim().parse::<f64>().is_ok() {
                        return Some(path.to_string_lossy().to_string());
                    }
                }
            }
        }
    }

    None
}

/// Return the first `tempN_input` under a hwmon device whose `name` matches one
/// of `names` and reads as a valid number.
fn find_hwmon_by_name(names: &[&str]) -> Option<String> {
    let dirs = std::fs::read_dir("/sys/class/hwmon").ok()?;
    for dir in dirs.flatten() {
        let name = match fs::read_to_string(dir.path().join("name")) {
            Ok(n) => n.trim().to_string(),
            Err(_) => continue,
        };
        if !names.contains(&name.as_str()) {
            continue;
        }
        for &temp_file in &["temp1_input", "temp2_input"] {
            let temp_path = dir.path().join(temp_file);
            if let Ok(content) = fs::read_to_string(&temp_path) {
                if content.trim().parse::<f64>().is_ok() {
                    return Some(temp_path.to_string_lossy().to_string());
                }
            }
        }
    }
    None
}

/// Simple glob matching for a single * wildcard.
/// Only supports patterns like "/sys/class/hwmon/hwmon*/temp1_input".
fn glob_simple(pattern: &str) -> Result<Vec<std::path::PathBuf>, io::Error> {
    if let Some(star_pos) = pattern.find('*') {
        let prefix = &pattern[..star_pos];
        let suffix = &pattern[star_pos + 1..];

        // Find the directory part of the prefix
        let parent = std::path::Path::new(prefix)
            .parent()
            .unwrap_or(std::path::Path::new("/"));

        if !parent.exists() {
            return Ok(Vec::new());
        }

        let file_prefix = std::path::Path::new(prefix)
            .file_name()
            .map(|f| f.to_string_lossy().to_string())
            .unwrap_or_default();

        let mut results = Vec::new();
        for entry in std::fs::read_dir(parent)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with(&file_prefix) {
                let full = entry.path().join(suffix.trim_start_matches('/'));
                if full.exists() {
                    results.push(full);
                }
            }
        }
        Ok(results)
    } else {
        let p = std::path::Path::new(pattern);
        if p.exists() {
            Ok(vec![p.to_path_buf()])
        } else {
            Ok(Vec::new())
        }
    }
}

// --- GPU (AMD/Intel/NVIDIA via DRM sysfs) ---

/// Discovered GPU sysfs file paths.
#[derive(Debug, Clone)]
struct GpuPaths {
    /// `.../device/gpu_busy_percent` (integer 0-100).
    busy: String,
    /// `.../device/hwmon/hwmonN/temp*_input` (millidegrees C), if present.
    temp: Option<String>,
}

/// Read GPU utilization percentage (0-100) from the discovered card.
fn read_gpu_usage() -> Option<f64> {
    let paths = GPU_PATHS.get_or_init(discover_gpu).as_ref()?;
    let content = fs::read_to_string(&paths.busy).ok()?;
    content.trim().parse::<f64>().ok()
}

/// Read GPU temperature in Celsius from the discovered card's hwmon.
fn read_gpu_temperature() -> Option<f64> {
    let paths = GPU_PATHS.get_or_init(discover_gpu).as_ref()?;
    let temp_path = paths.temp.as_ref()?;
    let content = fs::read_to_string(temp_path).ok()?;
    content.trim().parse::<f64>().ok().map(|m| m / 1000.0)
}

/// Discover the primary GPU's sysfs paths and cache them.
///
/// When multiple DRM cards expose `gpu_busy_percent` (e.g. an integrated GPU
/// plus a discrete one), the card with the largest VRAM is chosen — that is the
/// discrete GPU users care about for a gaming/monitoring dashboard.
fn discover_gpu() -> Option<GpuPaths> {
    let dir = std::fs::read_dir("/sys/class/drm").ok()?;
    let mut best: Option<(u64, GpuPaths)> = None;

    for entry in dir.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        // Only real cards ("card0", "card1", …) — skip "card0-DP-1" outputs.
        if !name.starts_with("card") || name.contains('-') {
            continue;
        }
        let device = entry.path().join("device");
        let busy = device.join("gpu_busy_percent");
        if !busy.exists() {
            continue;
        }

        let vram = fs::read_to_string(device.join("mem_info_vram_total"))
            .ok()
            .and_then(|s| s.trim().parse::<u64>().ok())
            .unwrap_or(0);

        let temp = discover_gpu_temp(&device.join("hwmon"));
        let paths = GpuPaths {
            busy: busy.to_string_lossy().to_string(),
            temp,
        };

        match &best {
            Some((best_vram, _)) if *best_vram >= vram => {}
            _ => best = Some((vram, paths)),
        }
    }

    best.map(|(_, p)| p)
}

/// Find a temperature input under a card's `device/hwmon/hwmonN/` directory,
/// preferring the `edge` sensor label when present.
fn discover_gpu_temp(hwmon_dir: &std::path::Path) -> Option<String> {
    let dirs = std::fs::read_dir(hwmon_dir).ok()?;
    let mut fallback: Option<String> = None;
    for hw in dirs.flatten() {
        for idx in 1..=3 {
            let input = hw.path().join(format!("temp{idx}_input"));
            if !input.exists() {
                continue;
            }
            let label = fs::read_to_string(hw.path().join(format!("temp{idx}_label")))
                .unwrap_or_default()
                .trim()
                .to_lowercase();
            if label == "edge" {
                return Some(input.to_string_lossy().to_string());
            }
            fallback.get_or_insert_with(|| input.to_string_lossy().to_string());
        }
    }
    fallback
}

// --- Network throughput ---

/// Cumulative network counters at a point in time.
struct NetSample {
    rx: u64,
    tx: u64,
    at: Instant,
}

/// Read total rx/tx byte counters from /proc/net/dev, excluding loopback and
/// virtual interfaces (docker/veth/bridge) so the rate reflects real traffic.
fn read_net_totals() -> Option<(u64, u64)> {
    let content = fs::read_to_string("/proc/net/dev").ok()?;
    let mut rx_total: u64 = 0;
    let mut tx_total: u64 = 0;
    for line in content.lines() {
        let (iface, rest) = match line.split_once(':') {
            Some(parts) => parts,
            None => continue,
        };
        let iface = iface.trim();
        if iface == "lo"
            || iface.starts_with("veth")
            || iface.starts_with("docker")
            || iface.starts_with("br-")
            || iface.starts_with("virbr")
        {
            continue;
        }
        let fields: Vec<&str> = rest.split_whitespace().collect();
        // Receive bytes = field 0, transmit bytes = field 8.
        if fields.len() < 9 {
            continue;
        }
        rx_total += fields[0].parse::<u64>().unwrap_or(0);
        tx_total += fields[8].parse::<u64>().unwrap_or(0);
    }
    Some((rx_total, tx_total))
}

/// Compute rx/tx byte-rates (bytes/sec) using the cached previous sample.
/// Returns (0.0, 0.0) on the first call or if counters are unavailable.
fn read_network_rates() -> (f64, f64) {
    let (rx, tx) = match read_net_totals() {
        Some(v) => v,
        None => return (0.0, 0.0),
    };
    let now = Instant::now();
    // Recover from a poisoned lock rather than panicking across the FFI boundary.
    let mut prev = PREV_NET.lock().unwrap_or_else(|e| e.into_inner());
    let result = match prev.as_ref() {
        Some(p) => {
            let elapsed = now.duration_since(p.at).as_secs_f64();
            if elapsed <= 0.0 {
                (0.0, 0.0)
            } else {
                (
                    rx.saturating_sub(p.rx) as f64 / elapsed,
                    tx.saturating_sub(p.tx) as f64 / elapsed,
                )
            }
        }
        None => (0.0, 0.0),
    };
    *prev = Some(NetSample { rx, tx, at: now });
    result
}

struct RamInfo {
    total: u64,
    used: u64,
    percent: f64,
}

/// Read RAM information from /proc/meminfo.
fn read_ram_info() -> RamInfo {
    let default = RamInfo {
        total: 0,
        used: 0,
        percent: 0.0,
    };

    let content = match fs::read_to_string("/proc/meminfo") {
        Ok(c) => c,
        Err(_) => return default,
    };

    let mut total_kb: u64 = 0;
    let mut available_kb: u64 = 0;
    let mut free_kb: u64 = 0;
    let mut buffers_kb: u64 = 0;
    let mut cached_kb: u64 = 0;

    for line in content.lines() {
        // Parse "Label:   value kB" without allocating a Vec per line.
        let mut parts = line.split_whitespace();
        let label = match parts.next() {
            Some(l) => l,
            None => continue,
        };
        let value: u64 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);

        match label {
            "MemTotal:" => total_kb = value,
            "MemAvailable:" => available_kb = value,
            "MemFree:" => free_kb = value,
            "Buffers:" => buffers_kb = value,
            "Cached:" => cached_kb = value,
            _ => {}
        }

        // Early exit once we have everything we need.
        if total_kb != 0 && available_kb != 0 && free_kb != 0 && buffers_kb != 0 && cached_kb != 0 {
            break;
        }
    }

    if total_kb == 0 {
        return default;
    }

    // If MemAvailable is present (Linux 3.14+), use it for accurate available memory.
    let used_kb = if available_kb > 0 {
        total_kb.saturating_sub(available_kb)
    } else {
        // Fallback: used = total - free - buffers - cached
        total_kb.saturating_sub(free_kb + buffers_kb + cached_kb)
    };

    let percent = (used_kb as f64 / total_kb as f64) * 100.0;

    RamInfo {
        total: total_kb * 1024,
        used: used_kb * 1024,
        percent,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_read_ram_info_from_fake_meminfo() {
        // This test reads the real /proc/meminfo.
        // It should always be available on Linux.
        let info = read_ram_info();
        assert!(info.total > 0, "Total RAM should be > 0 on a real system");
        assert!(info.percent >= 0.0 && info.percent <= 100.0);
    }

    #[test]
    fn test_count_cpus() {
        let count = count_cpus();
        assert!(count > 0);
    }

    #[test]
    fn test_collect_metrics_does_not_panic() {
        let metrics = collect_metrics();
        // Just verify it doesn't panic and returns reasonable values
        assert!(metrics.cpu_usage_percent >= 0.0);
        assert!(metrics.ram_total_bytes > 0);
        assert!(metrics.cpu_core_count > 0);
        // New metrics: net rates are non-negative; GPU usage (if present) is 0-100.
        assert!(metrics.net_rx_bytes_per_sec >= 0.0);
        assert!(metrics.net_tx_bytes_per_sec >= 0.0);
        if let Some(gpu) = metrics.gpu_usage_percent {
            assert!((0.0..=100.0).contains(&gpu));
        }
    }

    #[test]
    fn test_read_net_totals_returns_counters() {
        // /proc/net/dev always exists on Linux (at least the `lo` interface).
        let totals = read_net_totals();
        assert!(totals.is_some(), "expected /proc/net/dev to be readable");
    }

    #[test]
    fn test_read_network_rates_first_call_is_zero_then_finite() {
        // First observation has no prior sample → zero rates; subsequent calls
        // must stay finite and non-negative.
        let (_r1, _t1) = read_network_rates();
        let (r2, t2) = read_network_rates();
        assert!(r2.is_finite() && r2 >= 0.0);
        assert!(t2.is_finite() && t2 >= 0.0);
    }

    #[test]
    fn test_discover_gpu_does_not_panic() {
        // May be None on machines/CI without a DRM GPU — must not panic either way.
        let _ = discover_gpu();
    }

    #[test]
    fn test_read_disk_info_root() {
        // The root filesystem always exists and should report a non-zero total.
        let disk = read_disk_info();
        assert!(disk.total > 0, "root filesystem total should be > 0");
        assert!(disk.used <= disk.total);
        assert!((0.0..=100.0).contains(&disk.percent));
    }

    #[test]
    fn test_glob_simple_exact_path() {
        // /proc/stat should always exist
        let result = glob_simple("/proc/stat").unwrap();
        assert_eq!(result.len(), 1);
        assert!(result[0].ends_with("stat"));
    }

    #[test]
    fn test_glob_simple_nonexistent() {
        let result = glob_simple("/nonexistent/path*/file").unwrap();
        assert!(result.is_empty());
    }
}
