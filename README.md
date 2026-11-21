# Rent Eye Manager (iOS)

Native SwiftUI iPhone app for Rent Eye landlords, admins and staff.
It talks to the Rent Eye backend API (ASP.NET Core), which lives in the
separate `property-management-app` repository.

## Run it

1. Start the backend: in `property-management-app`, double-click `start-dev.command`
   (API on http://localhost:5050).
2. Open `RentEyeManager.xcodeproj` in Xcode (26 or later).
3. Pick an iPhone simulator and press Run (Command + R).
4. Sign in with an organisation account (owner, admin or staff).
   Platform admin and tenant accounts are not supported in this app.

The server address can be changed on the sign-in screen and in Settings.

## Layout

- `RentEyeManager/Core` – API client, models, session (Keychain), formatting,
  Ethiopian calendar, theme.
- `RentEyeManager/Screens` – sign-in, Home, Properties, Leases, Invoices,
  Payments, Settings.

Requires iOS 26.4.
