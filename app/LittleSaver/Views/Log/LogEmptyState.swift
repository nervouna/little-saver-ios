//
//  LogEmptyState.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import SwiftUI

struct LogEmptyState: View {
    var body: some View {
        VStack(spacing: 5) {
            Image("dropbox")
                .resizable()
                .frame(width: 75, height: 75)
                .padding(.bottom, 20)
                .accessibility(hidden: true)

            Text("Your Log is Empty")
                .font(.system(.title2, design: .rounded).weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.PrimaryText.opacity(0.8))

            Text("Press the plus button to add your first entry")
                .font(.system(.body, design: .rounded).weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.SubtitleText.opacity(0.7))
        }
        .padding(.horizontal, 30)
        .frame(height: 250, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
