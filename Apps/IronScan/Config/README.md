# App configuration

Signing and account settings are local or CI configuration and must not include secrets.
The checked-in `Apps/IronScan/IronScan.xcodeproj` is authoritative for the submission;
bootstrap and CI build it directly. `project.yml` is a supplemental XcodeGen structure,
not a replacement for the maintained project's complete package and file references.

The unused Firebase plist resource reference was removed, so a clean checkout does not
require an ignored Google service plist to build. Any existing local plist remains
ignored in this configuration directory; it is not published with the submission.
