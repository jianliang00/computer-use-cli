public protocol ComputerUseSessionAgent:
    PermissionStatusProviding,
    PermissionRequesting,
    RunningApplicationListing,
    ApplicationActivating,
    StateCapturing,
    ActionPerforming {}
