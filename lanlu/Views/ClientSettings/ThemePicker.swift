import SwiftUI
import UIKit

struct NativeSegmentedControl: UIViewRepresentable {
    @Binding var selection: String
    let items: [(icon: String, tag: String)]

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl()
        for (i, item) in items.enumerated() {
            control.insertSegment(with: UIImage(systemName: item.icon), at: i, animated: false)
        }
        control.selectedSegmentIndex = items.firstIndex(where: { $0.tag == selection }) ?? 0
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        uiView.selectedSegmentIndex = items.firstIndex(where: { $0.tag == selection }) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        let parent: NativeSegmentedControl
        init(_ parent: NativeSegmentedControl) { self.parent = parent }
        @objc func changed(_ sender: UISegmentedControl) {
            parent.selection = parent.items[sender.selectedSegmentIndex].tag
        }
    }
}
