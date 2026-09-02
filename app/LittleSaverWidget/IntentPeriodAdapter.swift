import LittleSaverCore

extension TimePeriod {
    var ledgerPeriod: LedgerTimePeriod {
        switch self {
        case .unknown: return .unknown
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }
}

extension InsightsTimePeriod {
    var ledgerPeriod: LedgerInsightsPeriod {
        switch self {
        case .unknown: return .unknown
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }
}
