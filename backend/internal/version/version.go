package version

// Set via -ldflags at build time.
var (
	Version = "dev"
	Commit  = "unknown"
)

func Full() string {
	if Commit == "unknown" || Commit == "" {
		return Version
	}
	return Version + "-" + Commit
}
