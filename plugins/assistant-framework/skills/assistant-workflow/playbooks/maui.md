# .NET MAUI Mobile App

**Architecture:** MVVM + Clean Architecture + Shell navigation

## Folder structure
```
src/
  Domain/
  Application/
  Infrastructure/
  MauiApp/
    Views/                # XAML pages
    ViewModels/           # One ViewModel per View
    Services/
    Controls/             # Custom controls
    Resources/
      Styles/             # Colors.xaml, Styles.xaml
      Fonts/
      Images/
    Platforms/             # Android/iOS specific code
    MauiProgram.cs         # DI composition root
tests/
  Domain.Tests/
  Application.Tests/
  MauiApp.Tests/
```

## Typical Discovery Q&A
```
1. Target platforms?
   a) Android + iOS  b) Android only  c) iOS + macOS  d) All
2. Navigation?
   a) Shell (tab + flyout, recommended)
   b) NavigationPage (stack)
   c) Custom
3. Local storage?
   a) SQLite  b) Preferences (key-value)  c) File-based  d) LiteDB
4. Offline-first?
   a) Yes — local DB with sync
   b) No — handle connectivity gracefully
5. MVVM toolkit?
   a) CommunityToolkit.Mvvm (recommended)
   b) Prism  c) ReactiveUI
```

## Architecture rules (Plan phase)
- ViewModels never reference Views or XAML types
- ViewModels depend on Application interfaces, not Infrastructure
- ICommand via RelayCommand (CommunityToolkit.Mvvm)
- Navigation via Shell routes, not direct page instantiation
- Platform-specific code: `#if ANDROID` / `#if IOS` or Platforms/
- No business logic in code-behind (.xaml.cs)
- DI registration in MauiProgram.cs

## Design rules (Design phase)
- All colors in Resources/Styles/Colors.xaml
- All styles in Resources/Styles/Styles.xaml (implicit + explicit)
- Platform-specific: `<OnPlatform>`, `<OnIdiom>`
- Touch targets minimum 48x48dp
- Test with light and dark AppTheme
- No hardcoded pixel values — use relative sizing
- Safe area handling (notch, bottom bar)
- Test on Android emulator and iOS simulator

## Build/test
```
dotnet build
dotnet test
dotnet build -t:Run -f net9.0-android
dotnet build -t:Run -f net9.0-ios
```
