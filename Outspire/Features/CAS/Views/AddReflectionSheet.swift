import Combine
import Foundation
import SwiftUI
import Toasts

struct AddReflectionSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.presentToast) private var presentToast
    @StateObject private var viewModel: AddReflectionViewModel
    @State private var showingLearningOutcomesSheet = false

    init(
        availableGroups: [ReflectionGroup],
        studentId: String,
        onSave: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: AddReflectionViewModel(
                availableGroups: availableGroups,
                studentId: studentId,
                onSave: onSave
            )
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Metadata")) {
                    Picker("Club", selection: $viewModel.selectedGroupId) {
                        ForEach(viewModel.availableGroups) { group in
                            Text(group.displayName).tag(group.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    TextField("Title...", text: $viewModel.title)
                }

                Section(
                    header: HStack {
                        Text("Summary")
                        Spacer()
                        Text("\(viewModel.summaryWordCount)/\(viewModel.summaryLimit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                ) {
                    TextEditor(text: $viewModel.summary)
                        .frame(minHeight: 60)
                        .background(Color.clear)
                        .overlay(alignment: .topLeading) {
                            if viewModel.summary.isEmpty {
                                Text(
                                    "You can select a paragraph from your reflection content as a summary."
                                )
                                .foregroundStyle(Color(UIColor.tertiaryLabel))
                                .padding(.top, 8)
                                .padding(.leading, 3)
                            }
                        }
                }

                Section(
                    header: HStack {
                        Text("Content")
                        Spacer()
                        Text("\(viewModel.contentWordCount) (min \(viewModel.contentMin))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                ) {
                    TextEditor(text: $viewModel.content)
                        .frame(minHeight: 120)
                        .background(Color.clear)
                        .overlay(alignment: .topLeading) {
                            if viewModel.content.isEmpty {
                                Text(
                                    "Write your detailed reflection here...\nAutosave is enabled, so your work is saved automatically."
                                )
                                .foregroundStyle(Color(UIColor.tertiaryLabel))
                                .padding(.top, 8)
                                .padding(.leading, 3)
                            }
                        }
                }

                Section(header: Text("Learning Outcomes")) {
                    Toggle(isOn: $viewModel.lo1) {
                        Label("Awareness", systemImage: "brain.head.profile")
                    }
                    .onChange(of: viewModel.lo1) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo2) {
                        Label("Challenge", systemImage: "figure.walk.motion")
                    }
                    .onChange(of: viewModel.lo2) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo3) {
                        Label("Initiative", systemImage: "lightbulb")
                    }
                    .onChange(of: viewModel.lo3) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo4) {
                        Label("Collaboration", systemImage: "person.2")
                    }
                    .onChange(of: viewModel.lo4) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo5) {
                        Label("Commitment", systemImage: "checkmark.seal")
                    }
                    .onChange(of: viewModel.lo5) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo6) {
                        Label("Global Value", systemImage: "globe.americas")
                    }
                    .onChange(of: viewModel.lo6) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo7) {
                        Label("Ethics", systemImage: "shield.lefthalf.filled")
                    }
                    .onChange(of: viewModel.lo7) { HapticManager.shared.playToggle() }

                    Toggle(isOn: $viewModel.lo8) {
                        Label("New Skills", systemImage: "wrench.and.screwdriver")
                    }
                    .onChange(of: viewModel.lo8) { HapticManager.shared.playToggle() }
                }

                // Learning Outcomes Explanation moved to a sheet shown via toolbar
            }
            .navigationTitle("New Reflection")
            .onChange(of: viewModel.errorMessage) { _, errorMessage in
                if let errorMessage {
                    let toast = ToastValue(
                        icon: Image(systemName: "exclamationmark.triangle").foregroundStyle(.red),
                        message: errorMessage
                    )
                    presentToast(toast)
                    // Reset error message after displaying toast
                    viewModel.errorMessage = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.playButtonTap()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(id: "llmSuggest", placement: .primaryAction) {
                    Menu {
                        Button {
                            HapticManager.shared.playButtonTap()
                            viewModel.fetchLLMSuggestion()
                        } label: {
                            Label("Suggest", systemImage: "pencil.and.scribble")
                        }
                        Button {
                            HapticManager.shared.playButtonTap()
                            viewModel.revertSuggestion()
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!viewModel.canRevertSuggestion)
                        Button(role: .destructive) {
                            HapticManager.shared.playDelete()
                            viewModel.clearForm()
                            let toast = ToastValue(
                                icon: Image(systemName: "trash").foregroundStyle(.red),
                                message: "Form cleared"
                            )
                            presentToast(toast)
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        if viewModel.isFetchingSuggestion {
                            ProgressView()
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    .disabled(viewModel.isFetchingSuggestion)
                }
                ToolbarItem(id: "learningOutcomesInfo", placement: .primaryAction) {
                    Button(action: {
                        HapticManager.shared.playButtonTap()
                        showingLearningOutcomesSheet.toggle()
                    }) {
                        Image(systemName: "info.circle")
                    }
                    .help("Help")
                }

                // Un-comment this after Xcode 26
                //                if #available(iOS 26.0, *) {
                //                    ToolbarSpacer(.fixed, placement: .primaryAction)
                //                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        HapticManager.shared.playFormSubmission()
                        viewModel.save()
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .interactiveDismissDisabled(true) // Force user to use buttons
        .onChange(of: viewModel.errorMessage) { _, err in
            if let msg = err {
                HapticManager.shared.playError()
                let toast = ToastValue(
                    icon: Image(systemName: "exclamationmark.triangle").foregroundStyle(.red),
                    message: msg
                )
                presentToast(toast)
            }
        }
        .onChange(of: viewModel.saveSucceeded) { _, ok in
            if ok {
                HapticManager.shared.playSuccessfulSave()
                let toast = ToastValue(
                    icon: Image(systemName: "checkmark.circle").foregroundStyle(.green),
                    message: "Reflection saved successfully"
                )
                presentToast(toast)
                presentationMode.wrappedValue.dismiss()
            }
        }
        .sheet(isPresented: $showingLearningOutcomesSheet) {
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    List {
                        Section(header: Text("Learning Outcomes")) {
                            VStack(alignment: .leading, spacing: 12) {
                                LearningOutcomeExplanationRow(
                                    icon: "brain.head.profile", title: "Awareness",
                                    explanation:
                                    "Increase your awareness of your strengths and areas for growth"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "figure.walk.motion", title: "Challenge",
                                    explanation: "Undertaken new challenges"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "lightbulb", title: "Initiative",
                                    explanation: "Planned and initiated activities"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "person.2", title: "Collaboration",
                                    explanation: "Worked collaboratively with others"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "checkmark.seal", title: "Commitment",
                                    explanation:
                                    "Shown perseverance and commitment on your activities"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "globe.americas", title: "Global Value",
                                    explanation: "Engaged with issues of global importance"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "shield.lefthalf.filled", title: "Ethics",
                                    explanation:
                                    "Considered the ethical implications of your actions"
                                )
                                LearningOutcomeExplanationRow(
                                    icon: "wrench.and.screwdriver", title: "New Skills",
                                    explanation: "Developed new skills"
                                )
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
                .navigationTitle("Reflection Help")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            HapticManager.shared.playButtonTap()
                            showingLearningOutcomesSheet = false
                        }
                    }
                }
            }
        }
        .alert(
            "DISCLAIMER",
            isPresented: $viewModel.showFirstTimeSuggestionAlert
        ) {
            Button("Agree & Proceed", role: .cancel) {
                viewModel.dismissFirstTimeSuggestionAlert()
            }
        } message: {
            Text(DisclaimerManager.fullDisclaimerText)
        }
        .alert(
            "Suggestion Completed",
            isPresented: $viewModel.showCompletedSuggestionAlert
        ) {
            Button("Agree", role: .cancel) {
                HapticManager.shared.playSuccessFeedback()
                viewModel.dismissCompletedSuggestionAlert()
            }
        } message: {
            Text(DisclaimerManager.shortDisclaimerText)
        }
        .alert(
            isPresented: Binding<Bool>(
                get: { viewModel.suggestionError != nil },
                set: { if !$0 { viewModel.suggestionError = nil } }
            )
        ) {
            Alert(
                title: Text("Suggestion Error"),
                message: Text(viewModel.suggestionError ?? ""),
                dismissButton: .default(Text("OK")) {
                    viewModel.suggestionError = nil
                }
            )
        }
    }
}
