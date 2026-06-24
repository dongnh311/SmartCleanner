import Foundation
import SwiftUI

@MainActor
final class AppContainer: ObservableObject {

    let db: AppDatabase
    let permissions: PermissionsService
    let sizeCalculator: FileSizeCalculator
    let ruleEngine: RuleEngine
    let quarantine: QuarantineService
    let systemJunkScanner: SystemJunkScanner
    let trashBinScanner: TrashBinScanner
    let hierarchicalScanner: HierarchicalScanner
    let largeFilesScanner: LargeFilesScanner
    let duplicateDetector: DuplicateDetector
    let imageSimilarity: ImageSimilarity
    let appScanner: AppScanner
    let leftoverDetector: LeftoverDetector
    let homebrewUpdater: HomebrewUpdater
    let sparkleUpdater: SparkleUpdater
    let processMonitor: ProcessMonitor
    let loginItems: LoginItemsService
    let memoryService: MemoryService
    let batteryService: BatteryService
    let malwareScanner: MalwareScanner
    let realtimeProtection: RealtimeProtectionService
    let privacyCleaner: PrivacyCleaner
    let permissionsReader: PermissionsReader
    let smartCareOrchestrator: SmartCareOrchestrator
    let systemMetrics: SystemMetrics
    let myToolsStore: MyToolsStore
    let mailAttachmentsScanner: MailAttachmentsScanner
    let photoJunkScanner: PhotoJunkScanner
    let networkSpeedService: NetworkSpeedService
    let sensorsService: SensorsService
    let gpuStatsService: GPUStatsService
    let publicIPService: PublicIPService
    let bluetoothService: BluetoothService
    let diskIOService: DiskIOService
    let systemActivityService: SystemActivityService
    let menuBarStatus: MenuBarStatusModel
    let appUsageLogger: AppUsageLogger
    let appMetadata = AppMetadataResolver()
    let cleanupResultsCache = CleanupResultsCache()
    let scrollDenoiser: ScrollDenoiserController

    /// Cross-window navigation requests. Set by MenuBarExtra; consumed by RootView.
    @Published var pendingNavigation: SidebarItem?
    /// Bumped to ask SmartCareView to auto-start a scan on next appearance.
    @Published var smartCareAutoRunToken: UUID?

    init() {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            Log.db.error("Failed to open shared database, falling back to in-memory: \(error.localizedDescription, privacy: .public)")
            do {
                database = try AppDatabase.inMemory()
            } catch {
                Log.db.fault("Even in-memory database failed: \(error.localizedDescription, privacy: .public)")
                preconditionFailure("Cannot create database: \(error)")
            }
        }
        self.db = database
        self.permissions = PermissionsService()
        self.sizeCalculator = FileSizeCalculator()

        let ruleEngine = RuleEngine()
        let quarantine = QuarantineService()
        self.ruleEngine = ruleEngine
        self.quarantine = quarantine
        self.systemJunkScanner = SystemJunkScanner(ruleEngine: ruleEngine, quarantine: quarantine)
        self.trashBinScanner = TrashBinScanner(quarantine: quarantine)
        self.mailAttachmentsScanner = MailAttachmentsScanner(quarantine: quarantine)
        self.photoJunkScanner = PhotoJunkScanner(quarantine: quarantine)
        self.hierarchicalScanner = HierarchicalScanner()
        self.largeFilesScanner = LargeFilesScanner()
        self.duplicateDetector = DuplicateDetector()
        self.imageSimilarity = ImageSimilarity()
        self.appScanner = AppScanner()
        self.leftoverDetector = LeftoverDetector()
        self.homebrewUpdater = HomebrewUpdater()
        self.sparkleUpdater = SparkleUpdater()
        self.processMonitor = ProcessMonitor()
        self.loginItems = LoginItemsService()
        self.memoryService = MemoryService()
        self.batteryService = BatteryService()
        self.malwareScanner = MalwareScanner(quarantine: quarantine)
        self.realtimeProtection = RealtimeProtectionService(quarantine: quarantine)
        self.privacyCleaner = PrivacyCleaner(quarantine: quarantine)
        self.permissionsReader = PermissionsReader()
        self.systemMetrics = SystemMetrics()
        self.myToolsStore = MyToolsStore()
        self.networkSpeedService = NetworkSpeedService()
        self.sensorsService = SensorsService()
        self.gpuStatsService = GPUStatsService()
        self.publicIPService = PublicIPService()
        self.bluetoothService = BluetoothService()
        self.diskIOService = DiskIOService()
        self.systemActivityService = SystemActivityService()
        self.scrollDenoiser = ScrollDenoiserController()

        self.menuBarStatus = MenuBarStatusModel(
            systemMetrics: systemMetrics,
            memoryService: memoryService,
            batteryService: batteryService,
            networkService: networkSpeedService,
            sensorsService: sensorsService,
            gpuService: gpuStatsService,
            processMonitor: processMonitor
        )

        self.smartCareOrchestrator = SmartCareOrchestrator(
            systemJunk: systemJunkScanner,
            trash: trashBinScanner,
            malware: malwareScanner,
            processes: processMonitor
        )

        self.appUsageLogger = AppUsageLogger(db: database, processMonitor: processMonitor)

        Log.app.info("AppContainer initialised")

        menuBarStatus.start()
        realtimeProtection.startIfEnabled()
        Task { [appUsageLogger] in await appUsageLogger.start() }

        Task { [ruleEngine, quarantine] in
            do {
                try await ruleEngine.loadSystemJunkRules()
            } catch {
                Log.scanner.error("Failed to load rules: \(error.localizedDescription, privacy: .public)")
            }
            await quarantine.purgeOld()
        }
    }
}
