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
