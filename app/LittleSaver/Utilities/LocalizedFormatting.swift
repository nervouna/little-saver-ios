import Foundation

func localizedCurrencyAmount(
    _ amount: Double,
    currencyCode: String,
    showCents: Bool,
    showPositiveSign: Bool = false,
    locale: Locale = .current
) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = showCents ? 2 : 0
    formatter.maximumFractionDigits = showCents ? 2 : 0
    if showPositiveSign, amount > 0 {
        formatter.positivePrefix = "+" + formatter.positivePrefix
    }
    return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(amount)"
}

func localizedDateInterval(
    from startDate: Date,
    to endDate: Date,
    locale: Locale = .current,
    timeZone: TimeZone = .current
) -> String {
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: startDate, to: endDate)
}

func localizedDate(
    _ date: Date,
    template: String,
    locale: Locale = .current,
    timeZone: TimeZone = .current
) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

func localizedFormat(
    _ key: String,
    bundle: Bundle = .main,
    locale: Locale = .current,
    arguments: [CVarArg]
) -> String {
    let format = NSLocalizedString(key, bundle: bundle, comment: "")
    return String(format: format, locale: locale, arguments: arguments)
}
