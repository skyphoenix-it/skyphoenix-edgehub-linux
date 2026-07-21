# User Personas

**Version:** 0.1.0-draft
**Status:** Phase 0 - Discovery
**Last Updated:** 2026-07-11

---

## Persona 1: Alex - The Productivity-Focused Developer

**Role:** Senior software engineer, remote worker
**Age:** 29
**OS:** CachyOS (Arch-based), KDE Plasma on Wayland
**Hardware:** Desktop with 3 monitors + Corsair Xeneon Edge in portrait orientation

### Goals
- Keep current task and priorities visible without cluttering primary workspace
- Monitor system resources (CPU, RAM, temps) during compilation and container workloads
- Control background music via the touchscreen without switching windows
- Reduce context-switching overhead during deep work sessions
- Track focus sessions with a visible timer

### Frustrations
- Existing solutions (Conky, browser dashboards) require too much configuration
- Browser-based dashboards consume RAM and feel laggy
- No Linux software properly supports the Xeneon Edge touchscreen
- Terminal-based monitoring tools require switching windows

### Workflow
1. Starts work → dashboard shows current task, focus timer, CPU/RAM
2. During deep work → dashboard shows only essential info, minimal distractions
3. Compiling → glances at CPU temp and utilization
4. Break time → timer notification, media controls for podcast
5. End of day → reviews focus session statistics

### Technical Proficiency
High. Comprehends config files, terminal, and Linux internals. Prefers configuration-as-code but appreciates a working GUI.

---

## Persona 2: Jordan - The ADHD/Attention-Conscious Creative

**Role:** Freelance designer and writer
**Age:** 34
**OS:** Ubuntu LTS, GNOME on Wayland
**Hardware:** Laptop + Xeneon Edge in landscape below primary monitor

### Goals
- Externalize current focus without adding visual noise
- See "what am I doing right now?" at a glance
- Use visual timers to maintain time awareness
- Avoid shame-based productivity tools
- Easily reset and restart when focus drifts
- Keep the display calm - no aggressive notifications

### Frustrations
- Most productivity tools are judgmental or gamified in manipulative ways
- Phone-based timers introduce distraction
- Complex task managers create overhead instead of reducing it
- Bright, animated interfaces are overstimulating

### Workflow
1. Morning → sets one primary goal and top 3 priorities on dashboard
2. Work session → focus timer counts up; dashboard shows only current task
3. Drift → glances at dashboard to re-orient; no judgment, just information
4. Break → gentle visual reminder, not an alarming popup
5. End of day → clears dashboard; no streak pressure

### Technical Proficiency
Moderate. Comfortable with GUI tools and basic terminal. Appreciates sensible defaults over extensive configuration.

### Accessibility Needs
- High-contrast mode preferred
- Reduced motion essential
- Large, readable text
- Calm color palette (no aggressive reds)
- Clear, unambiguous labels

---

## Persona 3: Marcus - The Linux Gamer

**Role:** IT systems administrator, avid gamer
**Age:** 26
**OS:** CachyOS, KDE Plasma on X11 (for gaming compatibility)
**Hardware:** High-end desktop, AMD GPU, Xeneon Edge in landscape above main monitor

### Goals
- Monitor GPU/CPU temps, FPS, and utilization while gaming
- See frame time and network latency without overlays that might trigger anti-cheat
- Switch dashboard profile automatically when a game launches
- Control Discord mute, audio devices, and media from touchscreen
- Restore productivity dashboard when game closes

### Frustrations
- MangoHud/GOverlay require per-game configuration
- Browser-based dashboards consume resources needed for gaming
- No integrated solution for game-aware dashboard switching
- Existing hardware monitors are ugly terminal tools

### Workflow
1. Desktop use → productivity dashboard with system metrics
2. Game launches → auto-switch to lightweight gaming dashboard (temps, FPS, latency)
3. Gaming → quick glance at Xeneon for temps and performance
4. Game closes → auto-restore previous dashboard
5. Between matches → media controls, Discord status check

### Technical Proficiency
High. Administers Linux systems professionally. Wants performance and configurability.

---

## Persona 4: Sam - The Ricing Enthusiast

**Role:** Computer science student
**Age:** 21
**OS:** Arch Linux, Hyprland (Wayland)
**Hardware:** Custom build, multiple monitors, Xeneon Edge in portrait

### Goals
- Create a visually stunning secondary display that matches their desktop aesthetic
- Customize every aspect: colors, fonts, layouts, animations
- Share dashboard configurations with the community
- Build custom widgets for specific use cases
- Experiment with unusual layouts and orientations

### Frustrations
- Most secondary-display tools are not customizable enough
- Closed-source tools cannot be extended
- Lack of community around Linux secondary displays
- Widget development requires learning entire UI frameworks

### Workflow
1. Designs custom dashboard layout matching Hyprland aesthetic
2. Creates dark OLED theme with custom accent colors
3. Shares configuration on GitHub/Discord
4. Iterates on layout based on community feedback
5. Builds a custom widget for university schedule

### Technical Proficiency
High. Comfortable building from source, writing configs, and contributing to open source.

---

## Persona 5: Taylor - The Non-Technical Remote Worker

**Role:** Marketing manager
**Age:** 38
**OS:** Ubuntu LTS, GNOME on X11 (corporate IT provisioned)
**Hardware:** Company laptop + Xeneon Edge in landscape

### Goals
- See calendar, tasks, and time at a glance
- Control music during work without switching windows
- Have a meeting countdown timer visible
- Set up the dashboard once and never touch configuration again
- Avoid anything that requires terminal or config files

### Frustrations
- Every secondary-display solution requires technical knowledge
- No "just works" option for the Xeneon Edge on Ubuntu
- Intimidated by Arch/wiki-heavy documentation
- Wants appliance-like reliability

### Workflow
1. IT installs the .deb package once
2. First-run wizard guides display selection and layout choice
3. Dashboard shows clock, calendar agenda, meeting timer, media controls
4. Never opens settings again unless adding a widget
5. Expects it to survive reboots, updates, and monitor reconnection

### Technical Proficiency
Low. Needs GUI for everything. Will abandon the product if it requires terminal use.

---

## Persona 6: Dana - The Widget Developer

**Role:** Full-stack developer, open-source contributor
**Age:** 31
**OS:** Fedora, GNOME on Wayland
**Hardware:** Laptop + Xeneon Edge in landscape

### Goals
- Build and share widgets for the Xeneon Edge platform
- Use a well-documented SDK with clear examples
- Reach users without needing to maintain a full application
- Write widgets in a familiar language (Rust, TypeScript, or QML)
- Have widgets reviewed and distributed through a community repository

### Frustrations
- No existing widget platform for secondary Linux displays
- Building standalone secondary-display apps requires too much boilerplate
- No standard for widget metadata, permissions, or lifecycle
- Existing "widget" platforms (KDE Plasma widgets, GNOME extensions) are desktop-specific

### Workflow
1. Reads SDK documentation and examples
2. Creates a widget with manifest, logic, and UI
3. Tests locally with validation tool
4. Submits to community repository
5. Receives feedback and iterates
6. Widget is available for installation by all users

### Technical Proficiency
High. Professional developer. Expects good documentation, clean APIs, and versioned compatibility.

---

## Persona Summary Matrix

| Persona | OS | DE | Orientation | Tech Level | Primary Need |
|---------|----|----|-------------|------------|--------------|
| Alex | CachyOS | KDE Wayland | Portrait | High | Productivity + metrics |
| Jordan | Ubuntu | GNOME Wayland | Landscape | Moderate | ADHD-friendly focus |
| Marcus | CachyOS | KDE X11 | Landscape | High | Gaming telemetry |
| Sam | Arch | Hyprland | Portrait | High | Customization |
| Taylor | Ubuntu | GNOME X11 | Landscape | Low | "Just works" |
| Dana | Fedora | GNOME Wayland | Landscape | High | Widget development |

