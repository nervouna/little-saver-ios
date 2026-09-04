//
//  NoteView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 14/5/22.
//

import LittleSaverCore
import Combine
import Foundation
import Popovers
import SwiftUI

struct NoteView: View {
    @Binding var note: String
    @Binding var focused: Bool

    @FocusState private var textFocused: Bool
    let characterLimit = 50

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var noteWidth: CGFloat {
        let fontSize: CGFloat = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)
        //        let fontSize: CGFloat = fontSize
        let systemFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let roundedFont: UIFont
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            roundedFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            roundedFont = systemFont
        }

        let attributes = [NSAttributedString.Key.font: roundedFont]

        let size = (note as NSString).size(withAttributes: attributes)

        let placeholder = String(localized: "Add Note")
        let placeholderSize = (placeholder as NSString).size(withAttributes: attributes)

        if !note.isEmpty {
            return size.width + 2
        } else {
            return placeholderSize.width
        }

        //        return max(size.width + 2, (placeholderSize.width + 1))
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.alignleft")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            //                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.SubtitleText)

            ZStack(alignment: .leading) {
                TextField("", text: $note)
                    .onReceive(Just(note)) { _ in limitText(characterLimit) }
                    .focused($textFocused)
                    .foregroundColor(Color.PrimaryText)

                if note.isEmpty {
                    Text("Add Note")
                        .foregroundColor(Color.SubtitleText)
                }
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            //            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(width: min(noteWidth, UIScreen.main.bounds.width / 1.5), alignment: .center)
        }
        .onTapGesture {
            textFocused = true
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .stroke(Color.Outline, lineWidth: 1.5)
        )
        .onChange(of: textFocused) { newValue in
            focused = newValue
        }
    }

    func limitText(_ upper: Int) {
        if note.count > upper {
            note = String(note.prefix(upper))
        }
    }
}
