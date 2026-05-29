public enum UsageLevel: Equatable {
    case low      // green  (<50%)
    case medium   // yellow (50–80%)
    case high     // red    (>=80%)

    public init(percentage: Double) {
        if percentage >= 80 { self = .high }
        else if percentage >= 50 { self = .medium }
        else { self = .low }
    }
}
