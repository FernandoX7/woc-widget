import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview
    case market
    case community

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: return Str.navigationOverview
        case .market: return Str.navigationMarket
        case .community: return Str.navigationCommunity
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .market: return "chart.candlestick"
        case .community: return "person.3.fill"
        }
    }
}

struct DashboardPageSwitcher: View {
    @Binding var selection: DashboardPage

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(DashboardPage.allCases) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .accessibilityLabel(Text(Str.navigationLabel))
    }
}
