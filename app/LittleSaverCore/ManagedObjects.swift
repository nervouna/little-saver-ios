import CoreData
import Foundation

// Explicit classes preserve the existing Objective-C entity identities across targets.

@objc(Budget)
public class Budget: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Budget> {
        NSFetchRequest<Budget>(entityName: "Budget")
    }

    @NSManaged public var amount: Double

    @NSManaged public var dateCreated: Date?

    @NSManaged public var green: Bool

    @NSManaged public var id: UUID?

    @NSManaged public var startDate: Date?

    @NSManaged public var type: Int16

    @NSManaged public var category: Category?
}

extension Budget: Identifiable {}

@objc(Category)
public class Category: NSManagedObject {
    @NSManaged public var recurringSeries: NSSet?
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Category> {
        NSFetchRequest<Category>(entityName: "Category")
    }

    @NSManaged public var colour: String?

    @NSManaged public var dateCreated: Date?

    @NSManaged public var emoji: String?

    @NSManaged public var id: UUID?

    @NSManaged public var income: Bool

    @NSManaged public var name: String?

    @NSManaged public var order: Int64

    @NSManaged public var budget: Budget?

    @NSManaged public var templates: NSSet?

    @NSManaged public var transactions: NSSet?
}

extension Category: Identifiable {}

@objc(MainBudget)
public class MainBudget: NSManagedObject {
    @NSManaged public var revision: Int64
    @NSManaged public var isDeletion: Bool
    @NSManaged public var singletonKey: String?
    @NSManaged public var deduplicationToken: String?
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MainBudget> {
        NSFetchRequest<MainBudget>(entityName: "MainBudget")
    }

    @NSManaged public var amount: Double

    @NSManaged public var dateCreated: Date?

    @NSManaged public var green: Bool

    @NSManaged public var startDate: Date?

    @NSManaged public var type: Int16
}

extension MainBudget: Identifiable {}

@objc(TemplateTransaction)
public class TemplateTransaction: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TemplateTransaction> {
        NSFetchRequest<TemplateTransaction>(entityName: "TemplateTransaction")
    }

    @NSManaged public var amount: Double

    @NSManaged public var id: UUID?

    @NSManaged public var income: Bool

    @NSManaged public var note: String?

    @NSManaged public var order: Int16

    @NSManaged public var recurringCoefficient: Int16

    @NSManaged public var recurringType: Int16

    @NSManaged public var category: Category?
}

extension TemplateTransaction: Identifiable {}

@objc(Transaction)
public class Transaction: NSManagedObject {
    @NSManaged public var materializedGenerationID: String?
    @NSManaged public var normalizedGenerationID: String?
    @NSManaged public var userEditedAt: Date?
    @NSManaged public var userEditToken: String?
    @NSManaged public var occurrenceIndex: Int64
    @NSManaged public var scheduleDateOverridden: Bool
    @NSManaged public var nextScheduledDate: Date?
    @NSManaged public var seriesID: String?
    @NSManaged public var occurrenceKey: String?
    @NSManaged public var deduplicationToken: String?
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Transaction> {
        NSFetchRequest<Transaction>(entityName: "Transaction")
    }

    @NSManaged public var amount: Double

    @NSManaged public var date: Date?

    @NSManaged public var day: Date?

    @NSManaged public var id: UUID?

    @NSManaged public var income: Bool

    @NSManaged public var month: Date?

    @NSManaged public var note: String?

    @NSManaged public var onceRecurring: Bool

    @NSManaged public var recurringCoefficient: Int16

    @NSManaged public var recurringType: Int16

    @NSManaged public var category: Category?
}

extension Transaction: Identifiable {}

@objc(RecurringSeries)
public class RecurringSeries: NSManagedObject {
    @NSManaged public var sourceIndex: Int64
    /// Every generation continues the same family's global occurrence sequence.
    public var occurrenceNamespace: String? {
        familyID ?? logicalID
    }
    @NSManaged public var sourceOccurrenceKey: String?
    @NSManaged public var sourceTransactionID: UUID?
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringSeries> {
        NSFetchRequest<RecurringSeries>(entityName: "RecurringSeries")
    }
    @NSManaged public var logicalID: String?
    @NSManaged public var familyID: String?
    @NSManaged public var deduplicationToken: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var stoppedAt: Date?
    @NSManaged public var timeZoneID: String?
    @NSManaged public var anchorDate: Date?
    @NSManaged public var nextDate: Date?
    @NSManaged public var nextIndex: Int64
    @NSManaged public var type: Int16
    @NSManaged public var coefficient: Int16
    @NSManaged public var note: String?
    @NSManaged public var amount: Double
    @NSManaged public var income: Bool
    @NSManaged public var category: Category?
}

@objc(RecurringSuppression)
public class RecurringSuppression: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringSuppression> {
        NSFetchRequest<RecurringSuppression>(entityName: "RecurringSuppression")
    }
    @NSManaged public var occurrenceKey: String?
}
