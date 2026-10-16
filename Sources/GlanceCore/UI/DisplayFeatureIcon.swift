import SwiftUI

struct DisplayFeatureIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol).font(.system(size: 20))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: 40, height: 40)
            .background(isOn ? Color.blue : Color.primary.opacity(0.08), in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
    }
}
