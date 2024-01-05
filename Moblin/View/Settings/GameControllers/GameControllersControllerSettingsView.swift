import SwiftUI

struct GameControllersControllerSettingsView: View {
    @EnvironmentObject var model: Model
    var gameController: SettingsGameController

    private func buttonText(button: SettingsGameControllerButton) -> String {
        switch button.function {
        case .scene:
            return "\(model.getSceneName(id: button.sceneId)) scene"
        default:
            return button.function.rawValue
        }
    }

    private func buttonColor(button: SettingsGameControllerButton) -> Color {
        switch button.function {
        case .unused:
            return .gray
        default:
            return .primary
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(gameController.buttons) { button in
                    NavigationLink(destination: GameControllersControllerButtonSettingsView(
                        button: button,
                        selection: button.function.rawValue,
                        sceneSelection: button.sceneId
                    )) {
                        HStack {
                            Image(systemName: button.name)
                            Spacer()
                            Text(buttonText(button: button))
                                .foregroundColor(buttonColor(button: button))
                        }
                    }
                }
            }
        }
        .navigationTitle("Controller")
        .toolbar {
            SettingsToolbar()
        }
    }
}
