//
//  FilteredSearchNewTransactionView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 14/5/22.
//

import LittleSaverCore
import Combine
import Foundation
import Popovers
import SwiftUI

struct FilteredSearchNewTransactionView: View {
    @FetchRequest<Transaction> private var transactions: FetchedResults<Transaction>

    var searchQuery: String
    var category: Category?

    var body: some View {
        ScrollView(.horizontal) {
            if transactions.count > 0 && category != nil {
                HStack {
                    ForEach(filterOutDupes(day: transactions)) { transaction in
                        Text(transaction.wrappedNote)
                    }
                }
            }
        }
    }

    init(searchQuery: String, category: Category?) {
        let beginPredicate = NSPredicate(
            format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(
            format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: [
            beginPredicate, containPredicate
        ])

        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(
                format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)

            let andPredicate = NSCompoundPredicate(
                type: .and, subpredicates: [compound, categoryPredicate])

            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: andPredicate)
        } else {
            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: compound)
        }

        self.searchQuery = searchQuery
        self.category = category
    }

    func filterOutDupes(day: FetchedResults<Transaction>) -> [Transaction] {
        var seen = [Transaction]()
        let filtered = day.filter { entity -> Bool in
            if seen.contains(where: { $0.wrappedNote == entity.wrappedNote }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        return filtered
    }
}
