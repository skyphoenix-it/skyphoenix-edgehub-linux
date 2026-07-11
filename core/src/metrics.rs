use std::fs;
use std::io;
use std::sync::Mutex;

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
}

/// Cached CPU times from the previous reading, for delta computation.
static PREV_CPU_TIMES: Mutex<Option<CpuTimes>> = Mutex::new(None);

/// Cached CPU core count (doesn't change at runtime).
static CPU_CORE_COUNT: std::sync::OnceLock<u32> = std::sync::OnceLock::new();

/// Cached CPU temperature sensor path.
static TEMP_SENSOR_PATH: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();

/// Collect current system metrics.
pub fn collect_metrics() -> SystemMetrics {
    // Read RAM info exactly once (previously this parsed /proc/meminfo 3×).
    let ram = read_ram_info();
    SystemMetrics {
        cpu_usage_percent: read_cpu_usage(),
        cpu_temp_celsius: read_cpu_temperature(),
        ram_usage_percent: ram.percent,
        ram_total_bytes: ram.total,
        ram_used_bytes: ram.used,
        cpu_core_count: get_cpu_core_count(),
    }
}

/// Read CPU usage from /proc/stat using cached previous sample.
/// No sleep needed — computes delta from the last call.
fn read_cpu_usage() -> f64 {
    let current = match read_proc_stat_cpu() {
        Some(c) => c,
        None => return 0.0,
    };

    let mut prev = PREV_CPU_TIMES.lock().unwrap();
    let result = match prev.as_ref() {
        Some(p) => {
            let idle1 = p.idle + p.iowait;
            let idle2 = current.idle + current.iowait;
            let total1: u64 = p.user
                + p.nice
                + p.system
                + p.idle
                + p.iowait
                + p.irq
                + p.softirq
                + p.steal;
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
    *CPU_CORE_COUNT.get_or_init(|| count_cpus())
}

/// Read CPU temperature from hwmon interfaces.
/// Sensor path is discovered once and cached.
fn read_cpu_temperature() -> Option<f64> {
    let sensor_path = TEMP_SENSOR_PATH.get_or_init(|| discover_temp_sensor());

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
fn discover_temp_sensor() -> Option<String> {
    // Common hwmon paths to check
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

    // Try k10temp for AMD CPUs, coretemp for Intel, acpitz for ACPI thermal
    if let Ok(dirs) = std::fs::read_dir("/sys/class/hwmon") {
        for dir in dirs.flatten() {
            let name_path = dir.path().join("name");
            if let Ok(name) = fs::read_to_string(&name_path) {
                if name.trim() == "k10temp" || name.trim() == "coretemp" || name.trim() == "acpitz"
                {
                    for &temp_file in &["temp1_input", "temp2_input"] {
                        let temp_path = dir.path().join(temp_file);
                        if temp_path.exists() {
                            if let Ok(content) = fs::read_to_string(&temp_path) {
                                if content.trim().parse::<f64>().is_ok() {
                                    return Some(temp_path.to_string_lossy().to_string());
                                }
                            }
                        }
                    }
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
