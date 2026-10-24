// Only the members this plugin uses, with the same names and namespaces as
// LaunchBox's Unbroken.LaunchBox.Plugins.dll (plugin API 13.x).
using Unbroken.LaunchBox.Plugins.Data;

namespace Unbroken.LaunchBox.Plugins
{
    public interface IGameLaunchingPlugin
    {
        void OnBeforeGameLaunching(IGame game, IAdditionalApplication app, IEmulator emulator);
        void OnAfterGameLaunched(IGame game, IAdditionalApplication app, IEmulator emulator);
        void OnGameExited();
    }
}

namespace Unbroken.LaunchBox.Plugins.Data
{
    public interface IGame
    {
        string Title { get; set; }
        string Platform { get; set; }
        string ApplicationPath { get; set; }
    }

    public interface IAdditionalApplication
    {
        string ApplicationPath { get; set; }
    }

    public interface IEmulator
    {
        string Title { get; set; }
    }
}
