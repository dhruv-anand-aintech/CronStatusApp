import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var cronManager:  CronManager
    @EnvironmentObject var agentManager: LaunchAgentManager
    @State private var selectedTab = 0   // 0 = Launch Agents, 1 = Cron Jobs

    var body: some View {
        TabView(selection: $selectedTab) {
            LaunchAgentsView()
                .tabItem { Label("Launch Agents", systemImage: "gearshape.2") }
                .tag(0)
            CronJobsView()
                .tabItem { Label("Cron Jobs",     systemImage: "clock") }
                .tag(1)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if cronManager.isLoading || agentManager.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task {
                        await cronManager.refresh()
                        await agentManager.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(cronManager.isLoading || agentManager.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .task {
            await cronManager.refresh()
            await agentManager.refresh()
        }
    }
}
