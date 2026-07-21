use std::cell::RefCell;
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

// CPU-usage and network-rate deltas are computed against the *previous* sample.
// These baselines are kept thread-local: the GUI thread and the metrics worker
// thread each collect on their own cadence, and a process-global baseline made
// them race - each poisoning the other's delta and producing spurious 100% /
// multi-GB/s spikes. Per-thread baselines give each caller a consistent series.
thread_local! {
    /// Previous `/proc/stat` CPU times for this thread, for delta computation.
    static PREV_CPU_TIMES: RefCell<Option<CpuTimes>> = const { RefCell::new(None) };
    /// Previous network counters + timestamp for this thread, for byte-rate deltas.
    static PREV_NET: RefCell<Option<NetSample>> = const { RefCell::new(None) };
}

/// Cached CPU core count (doesn't change at runtime).
static CPU_CORE_COUNT: std::sync::OnceLock<u32> = std::sync::OnceLock::new();

/// Upper bound on re-discovery attempts for a sysfs path that is currently
/// absent. Bounds the cost of retrying on systems that genuinely have no such
/// sensor, while still recovering from a *transient* boot-time absence (drivers
/// not yet loaded) instead of latching "unavailable" forever.
const MAX_DISCOVERY_ATTEMPTS: u32 = 12;

/// A lazily-discovered sysfs path with bounded retry. Unlike a `OnceLock`, a
/// `None` (not-yet-found) result is retried up to `MAX_DISCOVERY_ATTEMPTS` times
/// so a sensor that appears shortly after boot is eventually picked up.
struct Discovered<T> {
    value: Option<T>,
    attempts: u32,
}

impl<T> Discovered<T> {
    const fn new() -> Self {
        Self {
            value: None,
            attempts: 0,
        }
    }
}

/// Cached CPU temperature sensor path (bounded retry while absent).
static TEMP_SENSOR: Mutex<Discovered<String>> = Mutex::new(Discovered::new());

/// Cached GPU sysfs paths (busy + temperature), bounded retry while absent.
static GPU_PATHS: Mutex<Discovered<GpuPaths>> = Mutex::new(Discovered::new());

/// Return the cached value, or (re)run `discover` if it is still absent and the
/// retry budget is not yet exhausted. Once found, the value is cached for good.
fn get_or_discover<T: Clone>(
    cache: &Mutex<Discovered<T>>,
    discover: impl FnOnce() -> Option<T>,
) -> Option<T> {
    // Recover from a poisoned lock rather than panicking across the FFI boundary.
    let mut c = cache.lock().unwrap_or_else(|e| e.into_inner());
    if c.value.is_none() && c.attempts < MAX_DISCOVERY_ATTEMPTS {
        c.attempts += 1;
        c.value = discover();
    }
    c.value.clone()
}

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
    disk_info_from_statvfs(
        stat.f_blocks as u64,
        stat.f_bfree as u64,
        stat.f_bavail as u64,
        stat.f_frsize as u64,
    )
}

/// Pure computation of disk usage from raw `statvfs` counters, matching `df`'s
/// accounting. Extracted so it can be tested without a real syscall.
fn disk_info_from_statvfs(f_blocks: u64, f_bfree: u64, f_bavail: u64, f_frsize: u64) -> DiskInfo {
    let frsize = f_frsize;
    let total = f_blocks.saturating_mul(frsize);
    // `f_bavail` is space usable by unprivileged processes (what `df` reports as
    // "Avail"); `f_bfree` includes root-reserved blocks. Match `df`'s accounting:
    // Used = total - f_bfree, and percent is over the user-visible (used+avail).
    let avail = f_bavail.saturating_mul(frsize);
    let free_all = f_bfree.saturating_mul(frsize);
    if total == 0 {
        return DiskInfo {
            total: 0,
            used: 0,
            percent: 0.0,
        };
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
/// No sleep needed - computes delta from the last call.
fn read_cpu_usage() -> f64 {
    let current = match read_proc_stat_cpu() {
        Some(c) => c,
        None => return 0.0,
    };

    PREV_CPU_TIMES.with(|prev| {
        let mut prev = prev.borrow_mut();
        let result = match prev.as_ref() {
            Some(p) => cpu_usage_from_times(p, &current),
            None => 0.0,
        };
        *prev = Some(current);
        result
    })
}

/// Compute CPU utilization percentage from two `/proc/stat` samples.
/// Returns 0.0 when there is no forward progress between samples.
/// Extracted from `read_cpu_usage` so the delta math can be tested directly.
fn cpu_usage_from_times(prev: &CpuTimes, current: &CpuTimes) -> f64 {
    let idle1 = prev.idle + prev.iowait;
    let idle2 = current.idle + current.iowait;
    let total1: u64 = prev.user
        + prev.nice
        + prev.system
        + prev.idle
        + prev.iowait
        + prev.irq
        + prev.softirq
        + prev.steal;
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
        // `saturating_sub`: with real (monotonic) counters `idle_delta` never
        // exceeds `total_delta`, but computing the two deltas independently means
        // a non-monotonic input could underflow. Clamp to keep the ratio in 0..=1.
        (total_delta.saturating_sub(idle_delta) as f64 / total_delta as f64) * 100.0
    }
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
    parse_cpu_line(line)
}

/// Parse the aggregate `cpu ...` line of `/proc/stat` into [`CpuTimes`].
///
/// Format: `cpu  user nice system idle iowait irq softirq steal [guest ...]`.
/// Requires the 8 core counters (`user`..`softirq` plus the label); `steal`
/// (field 8) is optional and defaults to 0 on legacy kernels that omit it.
/// Returns `None` if there are fewer than 8 fields or any required field is
/// non-numeric. Extracted from `read_proc_stat_cpu` so it can be tested without
/// reading real `/proc/stat`.
fn parse_cpu_line(line: &str) -> Option<CpuTimes> {
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
/// Sensor path is discovered lazily, cached, and retried (bounded) while absent.
fn read_cpu_temperature() -> Option<f64> {
    let path = get_or_discover(&TEMP_SENSOR, discover_temp_sensor)?;
    let content = fs::read_to_string(&path).ok()?;
    millideg_to_celsius(&content)
}

/// Parse a sysfs millidegree-Celsius reading (e.g. `"38000"`) into Celsius
/// (`38.0`). Tolerates surrounding whitespace; returns `None` on non-numeric or
/// empty input. Every finite value is passed through, including negatives
/// (`"-1000"` → `-1.0`) - the caller reserves `None`, not `-1.0`, for "no sensor".
fn millideg_to_celsius(raw: &str) -> Option<f64> {
    let millideg = raw.trim().parse::<f64>().ok()?;
    Some(millideg / 1000.0)
}

/// Discover the CPU temperature sensor path and cache it.
///
/// Priority matters: a real CPU sensor is identified by its hwmon `name`
/// (k10temp/coretemp/…). The generic globs are only a last resort - if tried
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
    discover_temp_from_patterns(&patterns)
}

/// Return the first path matched by `patterns` (via [`glob_simple`]) whose
/// contents parse as a number. Extracted from `discover_temp_sensor` so the
/// last-resort scan can be tested against a temp directory.
fn discover_temp_from_patterns(patterns: &[&str]) -> Option<String> {
    for pattern in patterns {
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
    find_hwmon_by_name_in(std::path::Path::new("/sys/class/hwmon"), names)
}

/// Scan `hwmon_root` for a device whose `name` file matches one of `names` and
/// return its first numeric `tempN_input`. Extracted so the name-matching logic
/// can be tested against a synthetic hwmon tree rather than real `/sys`.
fn find_hwmon_by_name_in(hwmon_root: &std::path::Path, names: &[&str]) -> Option<String> {
    let dirs = std::fs::read_dir(hwmon_root).ok()?;
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
    let paths = get_or_discover(&GPU_PATHS, discover_gpu)?;
    let content = fs::read_to_string(&paths.busy).ok()?;
    content.trim().parse::<f64>().ok()
}

/// Read GPU temperature in Celsius from the discovered card's hwmon.
fn read_gpu_temperature() -> Option<f64> {
    let paths = get_or_discover(&GPU_PATHS, discover_gpu)?;
    let temp_path = paths.temp.as_ref()?;
    let content = fs::read_to_string(temp_path).ok()?;
    millideg_to_celsius(&content)
}

/// Discover the primary GPU's sysfs paths and cache them.
///
/// When multiple DRM cards expose `gpu_busy_percent` (e.g. an integrated GPU
/// plus a discrete one), the card with the largest VRAM is chosen - that is the
/// discrete GPU users care about for a gaming/monitoring dashboard.
fn discover_gpu() -> Option<GpuPaths> {
    let dir = std::fs::read_dir("/sys/class/drm").ok()?;
    let mut best: Option<(u64, GpuPaths)> = None;

    for entry in dir.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        // Only real cards ("card0", "card1", …) - skip "card0-DP-1" outputs.
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
    Some(parse_net_dev(&content))
}

/// Return true if `iface` is a virtual/local interface whose bytes should not
/// be counted toward real network throughput.
///
/// Besides loopback and container/bridge devices, VPN and tunnel interfaces
/// (tun*, tap*, wg*, tailscale*, zt*) are excluded: they carry the *same* bytes
/// as the underlying physical NIC, so counting both roughly doubles throughput.
fn is_excluded_iface(iface: &str) -> bool {
    iface == "lo"
        || iface.starts_with("veth")
        || iface.starts_with("docker")
        || iface.starts_with("br-")
        || iface.starts_with("virbr")
        || iface.starts_with("tun")
        || iface.starts_with("tap")
        || iface.starts_with("wg")
        || iface.starts_with("tailscale")
        || iface.starts_with("zt")
}

/// Sum rx/tx byte counters from `/proc/net/dev` contents, excluding virtual
/// interfaces. Extracted so it can be tested against synthetic content.
fn parse_net_dev(content: &str) -> (u64, u64) {
    let mut rx_total: u64 = 0;
    let mut tx_total: u64 = 0;
    for line in content.lines() {
        let (iface, rest) = match line.split_once(':') {
            Some(parts) => parts,
            None => continue,
        };
        let iface = iface.trim();
        if is_excluded_iface(iface) {
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
    (rx_total, tx_total)
}

/// Compute rx/tx byte-rates (bytes/sec) using the cached previous sample.
/// Returns (0.0, 0.0) on the first call or if counters are unavailable.
fn read_network_rates() -> (f64, f64) {
    let (rx, tx) = match read_net_totals() {
        Some(v) => v,
        None => return (0.0, 0.0),
    };
    let now = Instant::now();
    PREV_NET.with(|prev| {
        let mut prev = prev.borrow_mut();
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
    })
}

struct RamInfo {
    total: u64,
    used: u64,
    percent: f64,
}

/// Read RAM information from /proc/meminfo.
fn read_ram_info() -> RamInfo {
    let content = match fs::read_to_string("/proc/meminfo") {
        Ok(c) => c,
        Err(_) => {
            return RamInfo {
                total: 0,
                used: 0,
                percent: 0.0,
            }
        }
    };
    ram_info_from_meminfo(&content)
}

/// Parse RAM usage from `/proc/meminfo` contents. Prefers `MemAvailable`
/// (Linux 3.14+); otherwise falls back to `free + buffers + cached`.
/// Extracted so it can be tested against synthetic content.
fn ram_info_from_meminfo(content: &str) -> RamInfo {
    let default = RamInfo {
        total: 0,
        used: 0,
        percent: 0.0,
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
    fn test_read_ram_info_from_real_proc() {
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
        // May be None on machines/CI without a DRM GPU - must not panic either way.
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

    // --- Disk accounting (synthetic statvfs) ---

    #[test]
    fn test_disk_info_from_statvfs_matches_df() {
        // 100 blocks total, 20 free (incl. root reservation), 10 available to
        // users, 4096-byte fragments. df: Used = total - f_bfree.
        let d = disk_info_from_statvfs(100, 20, 10, 4096);
        assert_eq!(d.total, 100 * 4096);
        assert_eq!(d.used, (100 - 20) * 4096);
        // percent over (used + avail) = 80 / (80 + 10) blocks.
        let expected = (80.0 / 90.0) * 100.0;
        assert!((d.percent - expected).abs() < 1e-6, "percent={}", d.percent);
    }

    #[test]
    fn test_disk_info_from_statvfs_zero_total_is_default() {
        let d = disk_info_from_statvfs(0, 0, 0, 4096);
        assert_eq!(d.total, 0);
        assert_eq!(d.used, 0);
        assert_eq!(d.percent, 0.0);
    }

    #[test]
    fn test_disk_info_from_statvfs_zero_denominator_is_zero_percent() {
        // total > 0 but used + avail == 0 (all free, none available) → 0% (no
        // divide-by-zero). blocks=100, bfree=100 → used=0; bavail=0 → avail=0.
        let d = disk_info_from_statvfs(100, 100, 0, 4096);
        assert_eq!(d.total, 100 * 4096);
        assert_eq!(d.used, 0);
        assert_eq!(d.percent, 0.0);
    }

    // --- RAM parsing (synthetic /proc/meminfo) ---

    #[test]
    fn test_ram_info_uses_memavailable_when_present() {
        let meminfo = "\
MemTotal:       16000000 kB
MemFree:         1000000 kB
MemAvailable:    8000000 kB
Buffers:          500000 kB
Cached:          4000000 kB
";
        let info = ram_info_from_meminfo(meminfo);
        // used = total - available = 16000000 - 8000000 = 8000000 kB
        assert_eq!(info.total, 16_000_000 * 1024);
        assert_eq!(info.used, 8_000_000 * 1024);
        assert!(
            (info.percent - 50.0).abs() < 1e-6,
            "percent={}",
            info.percent
        );
    }

    #[test]
    fn test_ram_info_fallback_without_memavailable() {
        // No MemAvailable line → used = total - free - buffers - cached.
        let meminfo = "\
MemTotal:       16000000 kB
MemFree:         1000000 kB
Buffers:          500000 kB
Cached:          4000000 kB
";
        let info = ram_info_from_meminfo(meminfo);
        let used_kb = 16_000_000u64 - 1_000_000 - 500_000 - 4_000_000; // 10_500_000
        assert_eq!(info.used, used_kb * 1024);
        assert_eq!(info.total, 16_000_000 * 1024);
    }

    #[test]
    fn test_ram_info_empty_is_zeroed() {
        let info = ram_info_from_meminfo("");
        assert_eq!(info.total, 0);
        assert_eq!(info.used, 0);
        assert_eq!(info.percent, 0.0);
    }

    #[test]
    fn test_ram_info_skips_blank_lines_and_unknown_labels() {
        // A blank line (no first token) must be skipped, and an unrecognized
        // label (e.g. SwapTotal) must be ignored - not mis-parsed as a field.
        let meminfo = "\
MemTotal:       16000000 kB

SwapTotal:       2000000 kB
MemAvailable:    4000000 kB
";
        let info = ram_info_from_meminfo(meminfo);
        // used = total - available = 16000000 - 4000000 = 12000000 kB (75%).
        assert_eq!(info.total, 16_000_000 * 1024);
        assert_eq!(info.used, 12_000_000 * 1024);
        assert!(
            (info.percent - 75.0).abs() < 1e-6,
            "percent={}",
            info.percent
        );
    }

    // --- Network interface filtering (synthetic /proc/net/dev) ---

    /// One /proc/net/dev data line: iface + 16 numeric fields (rx bytes first,
    /// tx bytes at index 8).
    fn net_line(iface: &str, rx: u64, tx: u64) -> String {
        format!("{iface}: {rx} 0 0 0 0 0 0 0 {tx} 0 0 0 0 0 0 0\n")
    }

    #[test]
    fn test_parse_net_dev_excludes_local_and_container_ifaces() {
        let mut content = String::from(
            "Inter-|   Receive                                                |  Transmit\n\
             face |bytes    packets errs drop fifo frame compressed multicast|bytes\n",
        );
        content.push_str(&net_line("lo", 111, 111));
        content.push_str(&net_line("docker0", 222, 222));
        content.push_str(&net_line("veth123", 333, 333));
        content.push_str(&net_line("br-abcdef", 444, 444));
        content.push_str(&net_line("virbr0", 555, 555));
        content.push_str(&net_line("eth0", 1000, 2000));
        let (rx, tx) = parse_net_dev(&content);
        // Only eth0 should be counted.
        assert_eq!(rx, 1000, "loopback/container ifaces must be excluded");
        assert_eq!(tx, 2000);
    }

    #[test]
    fn test_is_excluded_iface_covers_local_and_container() {
        assert!(is_excluded_iface("lo"));
        assert!(is_excluded_iface("docker0"));
        assert!(is_excluded_iface("veth9a"));
        assert!(is_excluded_iface("br-1234"));
        assert!(is_excluded_iface("virbr0"));
        assert!(!is_excluded_iface("eth0"));
        assert!(!is_excluded_iface("enp3s0"));
        assert!(!is_excluded_iface("wlan0"));
    }

    #[test]
    fn bug_parse_net_dev_double_counts_vpn_tunnels() {
        // A VPN (wg0) and the physical iface (eth0) carry the SAME bytes; the
        // tunnel must be excluded or throughput is roughly doubled.
        let mut content = String::new();
        content.push_str(&net_line("eth0", 1000, 2000));
        content.push_str(&net_line("wg0", 1000, 2000)); // WireGuard, same bytes
        let (rx, tx) = parse_net_dev(&content);
        // Correct behavior: only physical eth0 counted.
        assert_eq!(
            rx, 1000,
            "BUG: tun/tap/wg/tailscale/zt interfaces are not excluded → VPN traffic double-counted"
        );
        assert_eq!(tx, 2000);
    }

    #[test]
    fn bug_is_excluded_iface_misses_tunnel_interfaces() {
        // Correct behavior: these tunnel/VPN interfaces should be excluded.
        assert!(
            is_excluded_iface("wg0"),
            "BUG: WireGuard (wg*) not excluded"
        );
        assert!(is_excluded_iface("tun0"), "BUG: tun* not excluded");
        assert!(is_excluded_iface("tap0"), "BUG: tap* not excluded");
        assert!(
            is_excluded_iface("tailscale0"),
            "BUG: tailscale* not excluded"
        );
        assert!(is_excluded_iface("zt0"), "BUG: ZeroTier (zt*) not excluded");
    }

    // --- CPU delta math (synthetic /proc/stat samples) ---

    fn cpu_times(user: u64, system: u64, idle: u64) -> CpuTimes {
        CpuTimes {
            user,
            nice: 0,
            system,
            idle,
            iowait: 0,
            irq: 0,
            softirq: 0,
            steal: 0,
        }
    }

    #[test]
    fn test_cpu_usage_from_times_half_load() {
        // Between samples: 50 ticks busy (user), 50 ticks idle → 50%.
        let prev = cpu_times(0, 0, 0);
        let cur = cpu_times(50, 0, 50);
        let usage = cpu_usage_from_times(&prev, &cur);
        assert!((usage - 50.0).abs() < 1e-6, "usage={}", usage);
    }

    #[test]
    fn test_cpu_usage_from_times_all_idle_is_zero() {
        let prev = cpu_times(10, 5, 100);
        let cur = cpu_times(10, 5, 200); // only idle advanced
        assert_eq!(cpu_usage_from_times(&prev, &cur), 0.0);
    }

    #[test]
    fn test_cpu_usage_from_times_no_progress_is_zero() {
        let prev = cpu_times(10, 5, 100);
        let cur = cpu_times(10, 5, 100); // identical → total_delta == 0
        assert_eq!(cpu_usage_from_times(&prev, &cur), 0.0);
    }

    #[test]
    fn test_cpu_usage_from_times_full_load() {
        let prev = cpu_times(0, 0, 0);
        let cur = cpu_times(100, 0, 0); // all busy
        let usage = cpu_usage_from_times(&prev, &cur);
        assert!((usage - 100.0).abs() < 1e-6, "usage={}", usage);
    }

    // --- Thread-safety smoke test for the shared global baselines ---

    #[test]
    fn test_collect_metrics_from_multiple_threads_stays_finite() {
        // read_cpu_usage / read_network_rates share process-global baselines
        // (PREV_CPU_TIMES / PREV_NET). Concurrent callers must not panic or
        // produce non-finite/negative values (guards against UB; the logic
        // race over the shared baseline is not directly asserted here).
        let handles: Vec<_> = (0..4)
            .map(|_| {
                std::thread::spawn(|| {
                    for _ in 0..25 {
                        let m = collect_metrics();
                        assert!(m.cpu_usage_percent.is_finite() && m.cpu_usage_percent >= 0.0);
                        assert!(
                            m.net_rx_bytes_per_sec.is_finite() && m.net_rx_bytes_per_sec >= 0.0
                        );
                        assert!(
                            m.net_tx_bytes_per_sec.is_finite() && m.net_tx_bytes_per_sec >= 0.0
                        );
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().expect("worker thread panicked");
        }
    }

    // --- Discovered<T> / get_or_discover bounded-retry semantics ---

    #[test]
    fn get_or_discover_caches_first_success() {
        let cache: Mutex<Discovered<u32>> = Mutex::new(Discovered::new());
        let calls = std::cell::Cell::new(0);
        // First call discovers and caches.
        let v = get_or_discover(&cache, || {
            calls.set(calls.get() + 1);
            Some(7)
        });
        assert_eq!(v, Some(7));
        // Subsequent calls return the cached value without re-running `discover`.
        let v2 = get_or_discover(&cache, || {
            calls.set(calls.get() + 1);
            Some(999)
        });
        assert_eq!(v2, Some(7));
        assert_eq!(
            calls.get(),
            1,
            "discover should run only once after success"
        );
    }

    #[test]
    fn get_or_discover_retries_up_to_the_bound_then_stops() {
        let cache: Mutex<Discovered<u32>> = Mutex::new(Discovered::new());
        let calls = std::cell::Cell::new(0);
        // A perpetually-absent sensor is retried, but only up to the bound.
        for _ in 0..(MAX_DISCOVERY_ATTEMPTS + 5) {
            let v = get_or_discover(&cache, || {
                calls.set(calls.get() + 1);
                None
            });
            assert_eq!(v, None);
        }
        assert_eq!(
            calls.get(),
            MAX_DISCOVERY_ATTEMPTS,
            "retries must be bounded by MAX_DISCOVERY_ATTEMPTS"
        );
    }

    #[test]
    fn get_or_discover_recovers_from_transient_absence() {
        let cache: Mutex<Discovered<u32>> = Mutex::new(Discovered::new());
        // Absent on the first two attempts, then appears - must be picked up.
        let attempt = std::cell::Cell::new(0);
        let mut last = None;
        for _ in 0..4 {
            last = get_or_discover(&cache, || {
                let a = attempt.get();
                attempt.set(a + 1);
                if a >= 2 {
                    Some(42)
                } else {
                    None
                }
            });
        }
        assert_eq!(last, Some(42));
    }

    // --- discover_gpu_temp over a synthetic hwmon directory ---

    #[test]
    fn discover_gpu_temp_prefers_edge_label() {
        let dir = tempfile::tempdir().unwrap();
        let hwmon = dir.path().join("hwmon0");
        std::fs::create_dir_all(&hwmon).unwrap();
        // temp1 is a non-edge sensor (fallback), temp2 is the edge sensor.
        std::fs::write(hwmon.join("temp1_input"), "40000").unwrap();
        std::fs::write(hwmon.join("temp1_label"), "junction").unwrap();
        std::fs::write(hwmon.join("temp2_input"), "38000").unwrap();
        std::fs::write(hwmon.join("temp2_label"), "edge").unwrap();

        let found = discover_gpu_temp(dir.path()).unwrap();
        assert!(found.ends_with("temp2_input"), "should prefer edge sensor");
    }

    #[test]
    fn discover_gpu_temp_falls_back_without_edge_label() {
        let dir = tempfile::tempdir().unwrap();
        let hwmon = dir.path().join("hwmon3");
        std::fs::create_dir_all(&hwmon).unwrap();
        std::fs::write(hwmon.join("temp1_input"), "45000").unwrap();
        // No label file → falls through to the first available input.
        let found = discover_gpu_temp(dir.path()).unwrap();
        assert!(found.ends_with("temp1_input"));

        // A directory with no temp inputs at all yields None.
        let empty = tempfile::tempdir().unwrap();
        assert!(discover_gpu_temp(empty.path()).is_none());
    }

    // --- CPU temp discovery over synthetic hwmon trees ---

    #[test]
    fn find_hwmon_by_name_in_matches_named_device() {
        let root = tempfile::tempdir().unwrap();
        // hwmon0: an unrelated NVMe sensor (must be skipped).
        let hwmon0 = root.path().join("hwmon0");
        std::fs::create_dir_all(&hwmon0).unwrap();
        std::fs::write(hwmon0.join("name"), "nvme\n").unwrap();
        std::fs::write(hwmon0.join("temp1_input"), "30000").unwrap();
        // hwmon1: the real CPU sensor.
        let hwmon1 = root.path().join("hwmon1");
        std::fs::create_dir_all(&hwmon1).unwrap();
        std::fs::write(hwmon1.join("name"), "k10temp\n").unwrap();
        std::fs::write(hwmon1.join("temp1_input"), "45000").unwrap();

        let found = find_hwmon_by_name_in(root.path(), &["k10temp", "coretemp"]).unwrap();
        assert!(found.starts_with(hwmon1.to_string_lossy().as_ref()));
        assert!(found.ends_with("temp1_input"));

        // No matching name → None.
        assert!(find_hwmon_by_name_in(root.path(), &["does-not-exist"]).is_none());
        // A device that matches by name but exposes no numeric temp → None.
        let hwmon2 = root.path().join("hwmon2");
        std::fs::create_dir_all(&hwmon2).unwrap();
        std::fs::write(hwmon2.join("name"), "acpitz\n").unwrap();
        assert!(find_hwmon_by_name_in(root.path(), &["acpitz"]).is_none());
        // A non-existent root is handled gracefully.
        assert!(find_hwmon_by_name_in(root.path().join("nope").as_path(), &["k10temp"]).is_none());
    }

    #[test]
    fn discover_temp_from_patterns_scans_and_validates() {
        let root = tempfile::tempdir().unwrap();
        // A device whose temp file holds non-numeric junk is skipped.
        let bad = root.path().join("sensorA");
        std::fs::create_dir_all(&bad).unwrap();
        std::fs::write(bad.join("temp"), "not-a-number").unwrap();
        // A device with a valid reading is selected.
        let good = root.path().join("sensorB");
        std::fs::create_dir_all(&good).unwrap();
        std::fs::write(good.join("temp"), "52000").unwrap();

        let pattern = format!("{}/sensor*/temp", root.path().to_string_lossy());
        let found = discover_temp_from_patterns(&[&pattern]).unwrap();
        assert!(found.ends_with("temp"));
        assert!(fs::read_to_string(&found)
            .unwrap()
            .trim()
            .parse::<f64>()
            .is_ok());

        // Patterns that match nothing → None.
        assert!(discover_temp_from_patterns(&["/nonexistent/zzz*/temp"]).is_none());
    }

    // --- millidegree → Celsius parsing (extracted from the temp readers) ---

    #[test]
    fn millideg_to_celsius_parses_scales_and_rejects_junk() {
        assert_eq!(millideg_to_celsius("38000"), Some(38.0));
        // A genuine negative reading is passed through, NOT treated as a sentinel.
        assert_eq!(millideg_to_celsius("-1000"), Some(-1.0));
        // Surrounding whitespace / trailing newline is tolerated.
        assert_eq!(millideg_to_celsius(" 45000\n"), Some(45.0));
        // Non-numeric and empty input → None.
        assert_eq!(millideg_to_celsius("junk"), None);
        assert_eq!(millideg_to_celsius(""), None);
    }

    // --- /proc/stat cpu-line parsing (extracted from read_proc_stat_cpu) ---

    #[test]
    fn parse_cpu_line_full_modern_line() {
        // cpu + user nice system idle iowait irq softirq steal guest guest_nice.
        let t = parse_cpu_line("cpu 10 20 30 40 50 60 70 80 90 100").unwrap();
        assert_eq!(t.user, 10);
        assert_eq!(t.nice, 20);
        assert_eq!(t.system, 30);
        assert_eq!(t.idle, 40);
        assert_eq!(t.iowait, 50);
        assert_eq!(t.irq, 60);
        assert_eq!(t.softirq, 70);
        assert_eq!(t.steal, 80);
    }

    #[test]
    fn parse_cpu_line_legacy_line_defaults_steal_to_zero() {
        // Legacy kernel: cpu + user nice system idle iowait irq softirq (8 fields,
        // no steal). steal must default to 0 rather than failing.
        let t = parse_cpu_line("cpu 1 2 3 4 5 6 7").unwrap();
        assert_eq!(t.softirq, 7);
        assert_eq!(t.steal, 0, "steal defaults to 0 when the field is absent");
    }

    #[test]
    fn parse_cpu_line_too_few_fields_is_none() {
        // Fewer than 8 fields (label + 6 counters) → None, no panic/index-OOB.
        assert!(parse_cpu_line("cpu 1 2 3 4 5 6").is_none());
    }

    #[test]
    fn cpu_usage_from_times_non_monotonic_is_clamped_to_zero() {
        // Non-monotonic counters: idle jumps forward while another counter drops,
        // so idle_delta (200) > total_delta (100). The saturating_sub must clamp
        // the busy fraction to 0.0 and never underflow/panic.
        let prev = cpu_times(100, 0, 0); // total = 100, idle = 0
        let cur = cpu_times(0, 0, 200); // total = 200, idle = 200
        let usage = cpu_usage_from_times(&prev, &cur);
        assert_eq!(usage, 0.0);
        assert!(usage.is_finite());
    }
}

#[cfg(test)]
mod proptests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// CPU utilization from any pair of counter samples stays within 0..=100
        /// and is always finite (guards against negative/overflow ratios).
        #[test]
        fn cpu_usage_is_always_bounded(
            u1 in 0u64..1_000_000, s1 in 0u64..1_000_000, i1 in 0u64..1_000_000,
            u2 in 0u64..1_000_000, s2 in 0u64..1_000_000, i2 in 0u64..1_000_000,
        ) {
            let prev = CpuTimes { user: u1, nice: 0, system: s1, idle: i1, iowait: 0, irq: 0, softirq: 0, steal: 0 };
            let cur  = CpuTimes { user: u2, nice: 0, system: s2, idle: i2, iowait: 0, irq: 0, softirq: 0, steal: 0 };
            let usage = cpu_usage_from_times(&prev, &cur);
            prop_assert!(usage.is_finite());
            prop_assert!((0.0..=100.0).contains(&usage), "usage out of range: {}", usage);
        }

        /// Disk usage percent derived from arbitrary statvfs counters is always a
        /// finite value in 0..=100.
        #[test]
        fn disk_percent_is_always_bounded(
            blocks in 0u64..1_000_000, bfree in 0u64..1_000_000,
            bavail in 0u64..1_000_000, frsize in 1u64..65536,
        ) {
            let d = disk_info_from_statvfs(blocks, bfree, bavail, frsize);
            prop_assert!(d.percent.is_finite());
            prop_assert!((0.0..=100.0).contains(&d.percent), "percent out of range: {}", d.percent);
            prop_assert!(d.used <= d.total);
        }

        /// RAM percent from arbitrary meminfo-shaped input is finite and in range.
        #[test]
        fn ram_percent_is_always_bounded(
            total in 0u64..64_000_000, avail in 0u64..64_000_000,
        ) {
            let content = format!("MemTotal: {total} kB\nMemAvailable: {avail} kB\n");
            let info = ram_info_from_meminfo(&content);
            prop_assert!(info.percent.is_finite());
            prop_assert!((0.0..=100.0).contains(&info.percent), "percent={}", info.percent);
        }
    }
}
