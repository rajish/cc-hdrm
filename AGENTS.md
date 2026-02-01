# Agent Instructions

## Protected Files — DO NOT MODIFY

The following files must **never** be modified unless the user explicitly instructs you to do so:

- `cc-hdrm/cc-hdrm/cc_hdrm.entitlements` — Xcode entitlements plist. Modifying or emptying this file breaks Keychain access and network permissions at runtime. If a task does not specifically require entitlement changes, leave this file untouched.

## Story Creation — File Path References

When creating stories, every reference to an existing project file **must** use a project-relative path (e.g., `cc-hdrm/cc-hdrm/Services/NotificationService.swift`), not just a filename. This eliminates unnecessary file searches by dev agents and saves tokens. Applies to all sections: Tasks, Dev Notes, File Structure Requirements, References, and inline code comments.
