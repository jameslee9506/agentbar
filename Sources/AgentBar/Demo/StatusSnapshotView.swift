import SwiftUI

struct StatusSnapshotView: View {
    let descriptors: [StatusItemDescriptor]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(descriptors) { descriptor in
                Image(nsImage: StatusItemImage.make(descriptor))
                    .renderingMode(.template).foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.background)
        .fixedSize()
    }
}
