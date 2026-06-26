# Roadmap — System Monitor parity with exelban/Stats

> Mục tiêu: bổ sung phần system-monitor để MacCleaner vừa là cleaner vừa là Stats-class monitor. Bốn tier theo ROI giảm dần. Mỗi item gồm scope, file dự kiến chạm, API/source nên dùng, và acceptance criteria.

## Tham chiếu

- Stats source: <https://github.com/exelban/stats>
- Stats modules: Battery, Bluetooth, CPU, Clock, Disk, GPU, Net, RAM, Sensors
- Stats widget kit: BarChart, Battery, Dot, Label, LineChart, Memory, Mini, NetworkChart, PieChart, Speed, Stack, Tachometer, Text

## Hiện trạng MacCleaner (5/2026)

**Đã có (system-monitor side):**
- CPU% total (qua `host_processor_info`) — `Core/Performance/SystemMetrics`
- RAM available (host_statistics64) — `Core/Performance/MemoryStats.swift`
- Battery percent + cycle count + condition (IOKit AppleSmartBattery) — `Core/Performance/BatteryStats.swift`
- Network up/down rate — `Core/Performance/NetworkSpeedService.swift`
- Process list (top by CPU/RAM) — `Core/Performance/ProcessMonitor.swift`
- Menu bar label hiển thị: CPU% • RAM% • Net up/down • battery%

**Chưa có:** GPU, sensors (temp/voltage/power/fan), per-core CPU, Bluetooth, Clock, history charts, public IP, notifications/alerts, menu-bar widget picker, localization.

---

## Tier 1 — Closing the obvious monitor gaps

### T1.1 — SMC sensor reader (CPU/GPU temp, fan RPM, power)

- **Why:** Gap rõ nhất so với Stats. iStat Menus / Stats users chờ điều này nhất.
- **Approach:** Dùng IOKit + SMC keys. Tham chiếu `Stats/Modules/Sensors/smc.swift`. Apple Silicon dùng IOReport, Intel dùng SMC keys cũ.
- **Files (dự kiến):**
  - `Core/Performance/SMCService.swift` — actor wrapping IOKit SMC keys
  - `Core/Performance/SensorReading.swift` — model
  - `Features/Performance/Sensors/SensorsView.swift` — full page
  - Sidebar: thêm `case sensors` vào `SidebarItem`, section `.performance`
- **Surface:**
  - Tile mới trong Mac Overview popover ("CPU 62°C • Fan 1800rpm")
  - Sidebar item "Sensors" liệt kê toàn bộ thermal zones, voltages, power
- **Acceptance:** Đọc được ít nhất CPU die temp, GPU die temp, fan RPM, system power draw trên Apple Silicon (M1+) và Intel.
- **Risks:** SMC keys khác giữa các SoC (M1/M2/M3/M4) → cần map theo machine model.

### T1.2 — GPU utilization

- **Why:** Stats có; người dùng creative pro hỏi nhiều.
- **Approach:** Apple Silicon: `IOReportSubscribe` channel "GPU Performance Statistics". Intel: SMC + Metal counters.
- **Files:**
  - `Core/Performance/GPUStats.swift`
  - Tile mới trong Mac Overview popover
  - (Optional) page riêng nếu metric đủ phong phú
- **Acceptance:** GPU% real-time, không vượt 5% CPU overhead khi sample 1Hz.

### T1.3 — Per-core CPU + load-average history

- **Why:** Stats line chart "60s history" rất iconic.
- **Approach:** Đã có `host_processor_info` per-CPU. Thêm rolling buffer 60 sample.
- **Files:**
  - `Core/Performance/SystemMetrics.swift` — extend trả về `[CoreSample]`
  - `Core/UI/SparklineView.swift` — reusable line chart (SwiftUI Canvas)
  - Update Process Monitor / new "CPU" page
- **Acceptance:** History chart 60s + per-core bar chart trong popover.

### T1.4 — Network history graph + public IP

- **Why:** Stats NetworkChart widget + Public IP là feature signature.
- **Approach:**
  - History: rolling buffer up/down/sec
  - Public IP: gọi <https://api.ipify.org> hoặc tự host (tránh third-party cho privacy — cho user opt-in)
  - VPN detection: `SCNetworkReachability` interface name (utun*)
- **Files:**
  - `Core/Performance/NetworkSpeedService.swift` — add history ring buffer
  - `Core/Performance/PublicIPService.swift` — opt-in fetch
  - `Features/Performance/Network/NetworkView.swift` — new page
- **Acceptance:** Line chart 60s, IP hiển thị (sau khi user opt-in trong Settings), VPN badge khi tunnel up.

---

## Tier 2 — UX competitive

### T2.1 — Menu bar widget picker (per-metric toggle)

- **Why:** Hiện tại menu bar label cố định. Stats cho phép bật/tắt từng widget.
- **Approach:** Settings tab "Menu Bar" với checkboxes: CPU / RAM / Net / Battery / Temp / Fan / GPU. Lưu UserDefaults. `MenuBarStatusLabel` đọc list và compose.
- **Files:**
  - `App/SettingsView.swift` — thêm tab Menu Bar
  - `Features/MenuBar/MenuBarStatusLabel.swift` — render theo config
  - `Features/MenuBar/MenuBarConfig.swift` (mới) — model + UserDefaults bridge
- **Acceptance:** User bật chỉ CPU+Temp → label chỉ show 2 cái đó, restart vẫn nhớ.

### T2.2 — Notifications / alerts engine

- **Why:** Smart Care chỉ chạy on-demand. Cần proactive alerts.
- **Approach:** Background service kiểm tra mỗi 5s, fire UNUserNotification khi rule trigger. Rules: CPU >90% sustained 30s, temp >95°C, fan stuck 0rpm, pin <10%, disk <5GB free, gradle daemon RAM >4GB.
- **Files:**
  - `Core/Alerts/AlertEngine.swift` — actor đánh giá rules
  - `Core/Alerts/AlertRule.swift` — model + builtin set
  - `Features/Alerts/AlertsView.swift` — Settings sub-page bật/tắt rule, thresholds
- **Acceptance:** 1 rule fire 1 notification trong 1 cooldown window (mặc định 10 phút). Test bằng cách load `yes > /dev/null` 1 phút.

### T2.3 — Bluetooth device list

- **Why:** Stats có. AirPods battery hiển thị ở menu bar là feature đáng tiền.
- **Approach:** `IOBluetooth` API (deprecated nhưng vẫn work). Hoặc `CBCentralManager` cho BLE. AirPods battery qua `IOBluetoothDevice.batteryPercent`.
- **Files:**
  - `Core/Performance/BluetoothService.swift`
  - `Features/Performance/Bluetooth/BluetoothView.swift`
  - Tile mới trong popover khi có thiết bị có pin
- **Acceptance:** List đầy đủ paired devices, hiện battery cho AirPods/Magic Mouse/Magic Keyboard.

---

## Tier 3 — Mở rộng scope

### T3.1 — Localization framework + Vietnamese

- **Why:** User là người Việt. Stats có 35+ ngôn ngữ. App hiện English only.
- **Approach:** Migrate strings sang `Localizable.xcstrings` (Xcode 15 string catalog). Bắt đầu với English (base) + Vietnamese.
- **Files:** Toàn bộ String literal user-facing → `String(localized:)`.
- **Acceptance:** Đổi system language sang VN → toàn bộ menu bar, sidebar, button text dịch đúng.
- **Risks:** Đại scope. Làm từng module một để giữ PR nhỏ.

### T3.2 — Per-disk I/O page

- **Why:** Space Lens chỉ show size. Cần read/write throughput history.
- **Approach:** `DASessionCreate` + `IORegistryEntry` IOBlockStorageDriver Statistics keys. Per-volume free space đã có qua `URLResourceValues`.
- **Files:**
  - `Core/Performance/DiskIOService.swift`
  - `Features/Performance/DiskMonitor/DiskMonitorView.swift`
- **Acceptance:** Per-volume MB/s read+write, free/used pie, mounted/unmounted state.

### T3.3 — Process top-N trong menu bar popover

- **Why:** Smart shortcut — Stats có Top Processes ở popover từng module.
- **Approach:** `Core/Performance/ProcessMonitor.swift` đã có. Reuse trong `MenuBarPopoverView`. Top 5 by CPU + 5 by RAM, click → mở Process Monitor page.
- **Files:** `Features/MenuBar/MenuBarPopoverView.swift` — thêm section "Top processes".
- **Acceptance:** 5 row trên popover, refresh 2Hz, click row → mở Process Monitor và highlight.

---

## Tier 4 — Nice-to-have

### T4.1 — Multi-timezone clock widget

- **Why:** Stats có. Không quan trọng cho cleaner nhưng tăng "đáng tiền".
- **Approach:** Settings list timezones. Render trong popover hoặc menu bar label config.
- **Files:** `Features/Clock/ClockService.swift`, `Features/Clock/ClockView.swift`.
- **Acceptance:** Add/remove timezones, format 12/24h.

### T4.2 — Sleep/wake/idle stats

- **Why:** Battery health hiểu hơn khi biết uptime/sleep ratio.
- **Approach:** `pmset -g log` parse OR `IOPMrootDomain` events. `host_load_info`.
- **Files:** Extend `Features/Performance/BatteryMonitor/BatteryMonitorView.swift`.
- **Acceptance:** Hiển thị uptime, last sleep, total sleep hours hôm nay, average daily sleep%.

### T4.3 — Sensor history charts (iStat Menus-style)

- **Why:** Trend curves cho temp/fan/power.
- **Approach:** SQLite ring (24h) + line chart trong Sensors page.
- **Files:** Extend SMC service + Sensors page.
- **Acceptance:** Mỗi sensor có sparkline 1h + chart 24h.

### T4.4 — Fan control (legacy)

- **Why:** Stats có, nhưng họ tự gọi "not maintained". Skip trừ khi user xin.
- **Status:** Defer.

---

## Order of execution (đề xuất sprint)

1. **Sprint 1** (T1.1): SMC sensor reader → menu bar tile
2. **Sprint 2** (T1.2 + T1.3): GPU + per-core CPU history
3. **Sprint 3** (T1.4): Network history + public IP
4. **Sprint 4** (T2.1): Menu bar widget picker
5. **Sprint 5** (T2.2): Alerts engine
6. **Sprint 6** (T2.3): Bluetooth
7. **Sprint 7** (T3.1): Localization VN — backbone
8. **Sprint 8** (T3.2): Disk I/O
9. **Sprint 9** (T3.3): Process top-N popover
10. **Sprint 10** (T4.1–4.3): Clock + sleep stats + sensor history

Mỗi sprint kết thúc khi build pass + user sanity-test ở môi trường thật (Apple Silicon + có Android Studio + Xcode chạy để verify cleaner protection vẫn vững).

---

## Cross-cutting concerns

- **Performance budget:** background services không vượt 1% CPU sample. Sensors là kẻ tiêu thụ lớn nhất — sample 2-5s, không 1s.
- **Energy:** Stats's FAQ ghi "Sensors + Bluetooth là 2 module ngốn nhất". MacCleaner phải cho user toggle off từng cái.
- **Privacy:** Public IP fetch phải opt-in, không gọi third party mặc định.
- **Sandbox:** SMC + IOReport cần IOKit private framework — giữ ngoài sandbox (đã ngoài sandbox sẵn).
- **Compatibility:** Apple Silicon là default target. Test trên Intel theo sample size có thể được.

---

## Outstanding bug + tech debt (theo dõi)

- [x] Live dev-tool protection (`WhitelistGuard.appProtectedExtras` + `LiveDevTools`) — **shipped 2026-05-08**.
- [x] Ancestor protection bug (xoá `Caches/Google` lấy luôn `Google/AndroidStudio`) — **shipped 2026-05-08**.
- [x] Menu-bar agent persistence khi Quit — **shipped 2026-05-08**.
- [x] Progress UI cho mọi cleaner — **shipped 2026-05-08**.
- [x] Tier 1 — SMC sensors + GPU + per-core CPU history + network history & public IP — **shipped 2026-05-08**.
- [x] Tier 2 — Menu bar widget picker + Alerts engine + Bluetooth — **shipped 2026-05-08**.
- [x] Tier 3 — Localization VN + Disk I/O page + Top processes popover — **shipped 2026-05-08**.
- [x] Tier 4 (T4.1–T4.3) — Multi-timezone clock + Sleep/uptime panel + Per-sensor history sparkline — **shipped 2026-05-08**. T4.4 (fan control) deferred.
- [x] App permission prompt cho Maintenance commands (DNS flush yêu cầu sudo) — **shipped 2026-06-26 (PR #12)**. `MaintenanceRunner` chạy lệnh trong app: non-admin qua `zsh`, admin qua `do shell script … with administrator privileges` (prompt hệ thống — không cần PrivilegedHelper/SMJobBless/Developer ID, hợp bản ad-hoc).
- [x] Updater (Sparkle) wiring — **đã có sẵn**. `UpdaterView` + `SparkleUpdater` (đọc `SUFeedURL` từ Info.plist mỗi app) + `HomebrewUpdater` đã hoạt động: cask có Upgrade, Sparkle app có Download/Notes. *Self-update của chính MacCleaner* không khả thi trên bản ad-hoc (Gatekeeper chặn bản cập nhật chưa notarize) — defer như ESF.
- [x] Smart Care: parallel scan — **đã có sẵn**. `SmartCareOrchestrator.run()` dùng `async let` chạy 4 pillar (junk/trash/malware/processes) đồng thời.
- [x] Localization xcstrings — **shipped 2026-06-26 (PR #13)**. Dịch nốt 197 chuỗi sâu còn lại → **324/324 keys có tiếng Việt**. Proper noun/abbrev/unit giữ nguyên.
