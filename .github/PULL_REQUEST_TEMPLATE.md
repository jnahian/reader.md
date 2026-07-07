## Summary

What does this change and why?

## Related issue

Closes #

## Testing

How did you verify it? (There's no test target — describe the manual check.)

- [ ] Built and ran with `swift run`
- [ ] Verified the affected flow in the app

## Checklist

- [ ] macOS 26-only APIs are guarded with a pre-26 fallback (deployment target is 13)
- [ ] Imperative actions follow the token-bump pattern on `AppState`
- [ ] Change is focused; matches surrounding code style
