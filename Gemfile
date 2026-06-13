# Ruby developer-toolchain dependencies for Pastura's release automation
# (ADR-014). This is NOT a runtime / SPM dependency — fastlane never links
# into the app binary; it only drives the local TestFlight upload step.
#
# fastlane's version is pinned by the committed Gemfile.lock, which is
# generated once at bootstrap with `bundle install` (fastlane is not
# vendored here). Run release tooling via `bundle exec fastlane ...` so the
# locked version is used. See ADR-014 § "Why fastlane".

source "https://rubygems.org"

gem "fastlane"
