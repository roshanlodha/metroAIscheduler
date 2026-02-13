import SwiftUI

struct GenerateView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate")
                .font(.title2)

            Button(action: viewModel.createSchedule) {
                if viewModel.isSolving {
                    ProgressView()
                } else {
                    Text("Create Schedule")
                }
            }
            .disabled(viewModel.isSolving)

            if !viewModel.validationIssues.isEmpty {
                GroupBox("Validation") {
                    ForEach(viewModel.validationIssues) { issue in
                        Text("• \(issue.message)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let diagnostic = viewModel.solverDiagnostic {
                GroupBox("Solver Diagnostics") {
                    Text(diagnostic.message)
                        .font(.headline)
                    ForEach(diagnostic.details, id: \.self) { detail in
                        Text("• \(detail)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}
