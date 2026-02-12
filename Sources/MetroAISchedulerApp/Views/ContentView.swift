import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationSplitView {
            List {
                Section("Project") {
                    Text(viewModel.project.name)
                }
                Section("Templates") {
                    ForEach(viewModel.project.shiftTemplates) { template in
                        Text(template.name)
                    }
                }
            }
            .navigationTitle("Metro AI Scheduler")
        } detail: {
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    ShiftTemplatesView(project: $viewModel.project, onChanged: viewModel.validate)
                        .tabItem { Label("Shift Templates", systemImage: "clock") }
                        .tag(0)

                    StudentsView(project: $viewModel.project)
                        .tabItem { Label("Students", systemImage: "person.3") }
                        .tag(1)

                    BlockRulesView(project: $viewModel.project, onChanged: viewModel.validate)
                        .tabItem { Label("Block + Rules", systemImage: "slider.horizontal.3") }
                        .tag(2)

                    GenerateView(viewModel: viewModel)
                        .tabItem { Label("Generate", systemImage: "wand.and.stars") }
                        .tag(3)

                    ResultsView(viewModel: viewModel)
                        .tabItem { Label("Results", systemImage: "calendar") }
                        .tag(4)
                }

                Divider()
                HStack {
                    Text(viewModel.statusMessage)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Load Project") { loadProject() }
                    Button("Save Project") { saveProject() }
                }
            }
        }
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadProject(from: url)
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "metro-project.json"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveProject(to: url)
        }
    }
}
