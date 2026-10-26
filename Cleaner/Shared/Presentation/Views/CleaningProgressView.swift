import SwiftUI

/// Progreso de una limpieza elemento a elemento: qué se está borrando, cuánto lleva, qué
/// falló y por qué, y un aviso cuando un elemento parece atascado.
struct CleaningProgressView: View {
    let viewModel: CleanerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if let current = viewModel.currentCleaning,
               let item = viewModel.cleaningQueue.first(where: { $0.id == current.id }) {
                CurrentCleaningCard(item: item, current: current)
            }

            LazyVStack(spacing: 0) {
                ForEach(viewModel.cleaningQueue) { item in
                    CleaningItemRow(
                        item: item,
                        outcome: viewModel.cleaningOutcomes[item.id],
                        isCurrent: viewModel.currentCleaning?.id == item.id
                    )
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassEffect(in: .rect(cornerRadius: 16))
        }
        .padding(.top, 20)
    }

    private var header: some View {
        let total = viewModel.cleaningQueue.count
        let finished = viewModel.finishedCleaningCount
        let failed = viewModel.cleaningOutcomes.values.count { !$0.succeeded }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Limpiando")
                    .font(.largeTitle.bold())
                Spacer()
                Button("Detener", systemImage: "stop.fill", action: viewModel.cancel)
                    .buttonStyle(.glass)
                    .help("Termina lo que está en curso y no toca el resto")
            }
            ProgressView(value: Double(finished), total: Double(max(total, 1)))
            HStack {
                Text("\(finished) de \(total) elementos · \(viewModel.cleanedBytesSoFar.byteString) liberados")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if failed > 0 {
                    Label("\(failed) con problemas", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

/// El elemento en curso, con su paso y el tiempo que lleva. Si tarda, explica qué suele retenerlo.
private struct CurrentCleaningCard: View {
    let item: ScanItem
    let current: CleanerViewModel.CurrentCleaning

    /// A partir de aquí se considera que el elemento puede estar atascado.
    private static let stallThreshold: TimeInterval = 15

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(current.since))
            let isStalled = elapsed >= Self.stallThreshold
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(current.step)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Duration.seconds(Int(elapsed)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(isStalled ? .orange : .secondary)
                        .contentTransition(.numericText())
                }
                Text(item.location)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isStalled {
                    Label {
                        Text("Está tardando más de lo normal. \(String(localized: item.removal.stallHint))")
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 16))
        }
    }
}

private struct CleaningItemRow: View {
    let item: ScanItem
    let outcome: CleaningItemOutcome?
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            status
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(isProblem ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(item.reclaimableBytes.byteString)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .opacity(outcome == nil && !isCurrent ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        switch outcome {
        case nil where isCurrent:
            ProgressView().controlSize(.mini)
        case nil:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .removed, .alreadyGone:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .trashed:
            Image(systemName: "trash.circle.fill").foregroundStyle(.green)
        case .disabled:
            Image(systemName: "bolt.slash.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var isProblem: Bool {
        if case .failed = outcome { true } else { false }
    }

    private var message: String? {
        switch outcome {
        case nil: isCurrent ? String(localized: "En curso…") : nil
        case .removed: nil
        case .alreadyGone: String(localized: "Ya no existía")
        case .trashed: String(localized: "En la Papelera")
        case .disabled: String(localized: "Desactivado")
        case .failed(let reason), .skipped(let reason): reason
        }
    }
}
