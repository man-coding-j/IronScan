enum PrototypeDemoMode {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
    static let minimumSegmentationConfidence = 0.50
    static let acceptedTongueAreaRatio = 0.08 ... 0.90
}
