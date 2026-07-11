import SwiftUI

struct CommunityPageView: View {
    var store: CommunityStore
    @Bindable var statusStore: StatusStore
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showingRecentReleases = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s12) {
                communitySnapshot
                latestRelease
                leaderboardCard
                communityLinks
            }
            .padding(.horizontal, Space.s16)
            .padding(.vertical, Space.s12)
        }
        .task { await store.refreshIfNeeded() }
        .refreshable { await store.refresh() }
    }

    private var communitySnapshot: some View {
        VStack(alignment: .leading, spacing: Space.s10) {
            sectionTitle(Str.communityTitle, systemImage: "globe.americas.fill")
            HStack(spacing: Space.s0) {
                CommunityMetric(
                    value: store.projectStats?.accountsCreated.map(Self.compactNumber) ?? Glyph.noValue,
                    label: Str.communityAccounts,
                    tint: Palette.cyan
                )
                StatDividerView()
                CommunityMetric(
                    value: store.currentRealm ?? store.projectStats?.realm ?? Glyph.noValue,
                    label: Str.communityRealm,
                    tint: Palette.green
                )
                StatDividerView()
                CommunityMetric(
                    value: realmContext,
                    label: store.realms.count > 1 ? Str.communityRealms : Str.communityRealmType,
                    tint: Palette.gold
                )
            }
            feedNotice(store.projectStatsState, feed: .projectStats)
            if store.realmsState.phase == .cached || store.realmsState.phase == .failed {
                feedNotice(store.realmsState, feed: .realms)
            }
        }
        .padding(Space.s12)
        .glassCard()
    }

    private var realmContext: String {
        if store.realms.count > 1 { return "\(store.realms.count)" }
        let selected = store.realms.first(where: { $0.name == store.currentRealm })
            ?? store.realms.first
        return selected?.type ?? Glyph.noValue
    }

    private var latestRelease: some View {
        let release = store.releases.first
        return VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s6) {
                sectionTitle(Str.communityLatestRelease, systemImage: "sparkles")
                Spacer()
                ContextualAlertButton(
                    isOn: $statusStore.releaseAlertsEnabled,
                    authorizationState: statusStore.notificationAuthorizationState,
                    visibleLabel: nil,
                    accessibilityLabel: AppText.releaseAlertLabel,
                    onHelp: AppText.releaseAlertDisableHelp,
                    offHelp: AppText.releaseAlertEnableHelp,
                    requestAuthorization: {
                        await statusStore.requestNotificationAuthorization()
                    }
                )
                if let tag = release?.tag {
                    Text(tag)
                        .font(Typo.pill)
                        .foregroundStyle(Palette.cyan)
                        .padding(.horizontal, Space.s7)
                        .padding(.vertical, Space.s2)
                        .background(Capsule().fill(Palette.cyan.opacity(Opacity.o13)))
                }
            }

            if let release {
                Text(release.name ?? release.tag ?? Glyph.noValue)
                    .font(Typo.emphasis)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let summary = Self.releaseSummary(release.body) {
                    Text(summary)
                        .font(Typo.bodyRounded)
                        .foregroundStyle(Palette.secondaryText(for: contrast))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let publishedAt = release.publishedAt {
                    Text(AppText.relativeDate(publishedAt, now: { store.currentDate }))
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.tertiaryText(for: contrast))
                }
                if let url = release.url {
                    Link(destination: url) {
                        Label(Str.communityViewRelease, systemImage: "arrow.up.right")
                            .font(Typo.buttonLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s7)
                            .overlay(Capsule().strokeBorder(Palette.cyan.opacity(Opacity.o30)))
                    }
                    .buttonStyle(GlassButtonStyle(shape: Capsule()))
                }
                if store.releases.count > 1 {
                    Divider().overlay(Palette.cardStroke)
                    DisclosureGroup(isExpanded: $showingRecentReleases) {
                        VStack(spacing: Space.s6) {
                            ForEach(Array(store.releases.dropFirst().prefix(2).enumerated()), id: \.offset) {
                                _, item in
                                RecentReleaseRow(release: item)
                            }
                        }
                        .padding(.top, Space.s6)
                    } label: {
                        Text(Str.communityRecentReleases)
                            .font(Typo.buttonLabel)
                            .foregroundStyle(Palette.secondaryText(for: contrast))
                    }
                    .tint(Palette.cyan)
                }
                feedNotice(store.releasesState, feed: .releases)
            } else if store.releasesState.phase == .idle
                        || store.releasesState.phase == .loading {
                CommunityLoadingRows()
            } else if store.releasesState.phase == .loaded {
                Label(Str.communityNoReleases, systemImage: "checkmark.circle")
                    .font(Typo.bodyRounded)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
            } else {
                feedNotice(store.releasesState, feed: .releases)
            }
        }
        .padding(Space.s12)
        .glassCard()
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: Space.s9) {
            sectionTitle(Str.communityLeaderboard, systemImage: "trophy.fill")
            ForEach(Array(store.leaderboard.prefix(3).enumerated()), id: \.offset) { index, entry in
                LeaderRow(
                    rank: entry.rank ?? index + 1,
                    name: entry.name ?? Glyph.noValue,
                    detail: Self.leaderDetail(entry)
                )
            }
            if store.leaderboard.isEmpty {
                if store.leaderboardState.phase == .idle
                    || store.leaderboardState.phase == .loading {
                    CommunityLoadingRows()
                } else if store.leaderboardState.phase == .loaded {
                    Label(Str.communityNoRankings, systemImage: "trophy")
                        .font(Typo.bodyRounded)
                        .foregroundStyle(Palette.secondaryText(for: contrast))
                } else {
                    feedNotice(store.leaderboardState, feed: .leaderboard)
                }
            } else {
                feedNotice(store.leaderboardState, feed: .leaderboard)
            }
        }
        .padding(Space.s12)
        .glassCard()
    }

    private var communityLinks: some View {
        HStack(spacing: Space.s8) {
            QuickLink(title: Str.actionDiscord, systemImage: "bubble.left.and.bubble.right.fill",
                      destination: AppLinks.discord, prominent: true)
            QuickLink(title: Str.actionGitHub, systemImage: "chevron.left.forwardslash.chevron.right",
                      destination: AppLinks.gameRepository)
            QuickLink(title: Str.actionWiki, systemImage: "book.closed.fill", destination: AppLinks.wiki)
            QuickLink(title: Str.actionHighScores, systemImage: "trophy.fill", destination: AppLinks.highScores)
        }
    }

    @ViewBuilder
    private func feedNotice<Value>(_ state: CommunityFeedState<Value>, feed: CommunityStore.Feed)
    -> some View where Value: Sendable & Equatable {
        switch state.phase {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            if state.value == nil {
                HStack(spacing: Space.s6) {
                    ProgressView().controlSize(.small)
                    Text(Str.communityLoading)
                        .font(Typo.placeholderHint)
                        .foregroundStyle(Palette.secondaryText(for: contrast))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(Str.communityLoading))
            }
        case .cached:
            CommunityFeedNotice(
                message: state.lastSuccess.map {
                    AppText.relativeUpdated($0, now: { store.currentDate })
                } ?? String(localized: "feed.showingCached", defaultValue: "Showing cached data"),
                tint: Palette.gold
            ) { Task { await store.refresh(feed) } }
        case .failed:
            CommunityFeedNotice(
                message: String(localized: "community.unavailable",
                                defaultValue: "Community data is unavailable"),
                tint: Palette.red
            ) { Task { await store.refresh(feed) } }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Typo.sectionLabel)
            .tracking(Tracking.t08)
            .foregroundStyle(Palette.secondaryText(for: contrast))
            .accessibilityAddTraits(.isHeader)
    }

    private static func compactNumber(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    private static func releaseSummary(_ body: String?) -> String? {
        body?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("**Release:") && !$0.hasPrefix("**Date:") && !$0.hasPrefix("**Previous") }
    }

    private static func leaderDetail(_ entry: LifetimeLeaderboardEntry) -> String {
        let level = entry.virtualLevel ?? entry.level
        let className = entry.characterClass?.capitalized
        return [
            className,
            level.map(AppText.communityLevel),
            entry.lifetimeXP.map { AppText.communityXP(compactNumber($0)) },
            entry.prestigeRank.flatMap { $0 > 0 ? AppText.communityPrestige($0) : nil },
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct CommunityFeedNotice: View {
    let message: String
    let tint: Color
    let retry: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Space.s6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(Typo.placeholderHint)
                .foregroundStyle(Palette.secondaryText(for: contrast))
                .lineLimit(2)
            Spacer(minLength: Space.s4)
            Button(action: retry) {
                Text(Str.feedRetry)
                    .font(Typo.statLabel)
                    .foregroundStyle(Palette.cyan)
                    .padding(.horizontal, Space.s7)
                    .padding(.vertical, Space.s4)
                    .overlay(Capsule().strokeBorder(Palette.cyan.opacity(Opacity.o30)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CommunityLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.r7)
                    .fill(Palette.cardStroke)
                    .frame(width: index == 1 ? 190 : 240, height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Str.communityLoading))
    }
}

private struct RecentReleaseRow: View {
    let release: GameRelease

    var body: some View {
        Group {
            if let url = release.url {
                Link(destination: url) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: Space.s8) {
            Text(release.tag ?? Glyph.noValue)
                .font(Typo.pill)
                .foregroundStyle(Palette.cyan)
            Text(release.name ?? release.tag ?? Glyph.noValue)
                .font(Typo.bodyRounded)
                .foregroundStyle(Palette.textSecond)
                .lineLimit(1)
            Spacer()
            if release.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(Typo.chevron)
                    .foregroundStyle(Palette.textTert)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct CommunityMetric: View {
    let value: String
    let label: LocalizedStringKey
    var tint: Color = Palette.textPrimary
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Space.s2) {
            Text(value)
                .font(Typo.statValue)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(Typo.statLabel)
                .foregroundStyle(Palette.tertiaryText(for: contrast))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}

private struct LeaderRow: View {
    let rank: Int
    let name: String
    let detail: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Space.s8) {
            Text("\(rank)")
                .font(Typo.statValue)
                .monospacedDigit()
                .foregroundStyle(rank == 1 ? Palette.gold : Palette.tertiaryText(for: contrast))
                .frame(width: Size.leaderboardRankWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(name).font(Typo.rowLabel).foregroundStyle(Palette.textPrimary).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(Typo.timestamp).foregroundStyle(Palette.tertiaryText(for: contrast))
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppText.communityLeaderAccessibility(rank: rank, name: name, detail: detail)))
    }
}

struct QuickLink: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL
    var prominent = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Link(destination: destination) {
            VStack(spacing: Space.s4) {
                Image(systemName: systemImage)
                    .font(Typo.iconMedium)
                    .accessibilityHidden(true)
                Text(title).font(Typo.pill).lineLimit(1)
            }
            .foregroundStyle(prominent ? Palette.cyan : Palette.secondaryText(for: contrast))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s8)
            .overlay(RoundedRectangle(cornerRadius: Radius.r8).strokeBorder(Palette.cardStroke))
        }
        .buttonStyle(GlassButtonStyle(shape: RoundedRectangle(cornerRadius: Radius.r8)))
    }
}

/// Local divider to avoid exposing the overview card's private implementation.
private struct StatDividerView: View {
    var body: some View {
        Rectangle().fill(Palette.cardStroke).frame(width: Size.dividerWidth, height: Size.dividerHeight)
    }
}
