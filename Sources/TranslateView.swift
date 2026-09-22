import AppKit
import SwiftUI

/// The whole app, in one screen: pick two languages, type on the left, read on
/// the right.
struct TranslateView: View {
    @EnvironmentObject private var settings: ProviderSettings
    @StateObject private var model: TranslatorViewModel

    @State private var showingSetup = false
    @State private var didCopy = false

    init(settings: ProviderSettings) {
        _model = StateObject(wrappedValue: TranslatorViewModel(settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            languageBar
            Divider()
            panes
            Divider()
            statusBar
        }
        .frame(minWidth: 780, minHeight: 440)
        .onAppear {
            // First launch lands in setup, so a local model can be wired up
            // before the first translation rather than after a confusing failure.
            if !settings.didCompleteSetup { showingSetup = true }
        }
        .sheet(isPresented: $showingSetup) {
            SetupView(isPresented: $showingSetup)
                .environmentObject(settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showProviderSetup)) { _ in
            showingSetup = true
        }
        .onChange(of: settings.targetLanguage) { _ in model.refreshIfNeeded() }
        .onChange(of: settings.sourceLanguage) { _ in model.refreshIfNeeded() }
    }

    // MARK: - Language bar

    private var languageBar: some View {
        HStack(spacing: 12) {
            languagePicker(selection: $settings.sourceLanguage, options: Language.sourceCatalog)

            Button(action: model.swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canSwapLanguages)
            .help(model.canSwapLanguages
                  ? "Swap languages (⌘⇧S)"
                  : "Pick a source language to swap")
            .keyboardShortcut("s", modifiers: [.command, .shift])

            languagePicker(selection: $settings.targetLanguage, options: Language.catalog)

            Spacer()

            Button {
                showingSetup = true
            } label: {
                Label(settings.kind.displayName, systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .help("Change translation backend")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func languagePicker(selection: Binding<String>, options: [Language]) -> some View {
        Picker("", selection: selection) {
            ForEach(options) { language in
                Text(language.name).tag(language.code)
            }
        }
        .labelsHidden()
        .frame(width: 210)
    }

    // MARK: - Panes

    private var panes: some View {
        HStack(spacing: 0) {
            inputPane
            Divider()
            outputPane
        }
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $model.input)
                .font(.system(size: 17))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("Enter text")
                            .font(.system(size: 17))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Text("\(model.input.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Clear", action: model.clear)
                    .buttonStyle(.borderless)
                    .disabled(model.input.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(model.output)
                    .font(.system(size: 17))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 17)
                    .padding(.top, 13)
            }
            .overlay(alignment: .topLeading) {
                if model.output.isEmpty && !model.isTranslating {
                    Text("Translation")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                }
            }

            HStack(spacing: 8) {
                if model.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Button("Stop", action: model.cancel)
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button(didCopy ? "Copied" : "Copy", action: copyOutput)
                    .buttonStyle(.borderless)
                    .disabled(model.output.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(model.errorMessage == nil ? "Translate" : "Try Again", action: model.translateNow)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canTranslate || model.isTranslating)
                .help("Translate now (⌘↩)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.output, forType: .string)

        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}

extension Notification.Name {
    /// Raised by the File menu so the setup sheet can be reopened later.
    static let showProviderSetup = Notification.Name("xyz.ignoresolutions.vibetranslate.showSetup")
}
