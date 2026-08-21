# Pipo UI behavior

Pipo is a read-only menu-bar companion for https://lms.lpucavite.edu.ph.
The menu-bar window is 420 by 620 points. The UI uses system colors with
maroon and gold accents. Toolbar controls may use Liquid Glass on macOS 26;
macOS 14 and later use a material fallback.

## Desktop companion

Launching Pipo from Applications opens a compact desktop window. Signed-out
students see onboarding and authentication. Signed-in students see account
status, connection controls, preferences, update checks, and sign out. The
menu-bar window remains the fast dashboard for Today and Courses.

## Entry and authentication

- The first screen offers school-account sign-in and access-token sign-in.
- Password sign-in sends the username and password to the model's one-time
  exchange action. The UI clears the password immediately after submission.
- Token sign-in clears the token field after submission. The model owns secure
  token persistence.
- The LMS origin is fixed and the browser link opens that origin only.
- Sign-in errors remain in the onboarding flow and offer another attempt.

## Today

Today shows Next up, Schedule, smart deadline groups, announcements, recent
messages, grade feedback, and recent resources. New assignments remove IDs
already present in due soon. Notification, message, and grade-feedback rows
show course and title metadata. They do not show message text or grade text.
Rows open an LMS destination when the model supplies one.

Today supports cached search and filters by course and item type. Students can
copy item details, add dated items to Calendar through the AppCore action hook,
snooze local reminders, and mark items seen. Failed sections expose their own
retry action. Empty sections stay collapsed.

The empty state explains that the day has no returned items. Loading shows a
progress state. Offline state retains and labels the cached dashboard. A
reconnect action asks the model to refresh. Partial failures name the affected
sections and keep the returned sections visible.

## Courses

Courses are limited to the published course list. Selecting a course opens a
detail view with the course name, short name, published grade, assignments,
announcements, and resources when supported. Courses support search, pinning,
and hiding. Hidden courses remain recoverable from the course filter menu. No
edit or submission action is presented.

## Settings and updates

Settings exposes grouped Connection, Sync, Reminders, Capabilities, Storage,
Updates, Diagnostics, and About controls. It includes refresh-now, cache-clear,
quiet hours, reminder switches, update channel, redacted diagnostics export,
and hidden-course recovery. Terra's model owns sensitive persistence; UI-only
preferences use UserDefaults until AppCore action hooks are wired.

The optional update action is a hook for the app's updater. The banner is
hidden when no updater action is supplied.

## Terra integration assumptions

The current model exposes phase, selectedTab, snapshot, settings,
authenticationError, signIn, refresh, openURL, and signOut. The default
PipoRootView initializer maps those values into the UI and calls the model
operations. PipoUIConfiguration remains available for focused UI tests and
for a future model variant.

The model's DashboardSnapshot is mapped into the privacy-shaped UI snapshot.
The UI reads only course and title metadata for notifications, messages, and
grade feedback. Destination opening returns to the model so its origin policy
remains in force.

The model owns cached data and the 15-minute refresh cadence. The UI keeps
returned cached data visible during offline state. Password input is cleared
before the sign-in operation is handed to the model; the model performs the
one-time exchange and token persistence. v0.3 mapping consumes new contract
fields with empty defaults for older snapshots.
