// Central site metadata — single source for links, commands & author.
export const repo = "https://github.com/jnahian/reader.md";
export const releasesLatest = `${repo}/releases/latest`;
export const releases = `${repo}/releases`;
export const website = "https://reader-md.jnahian.me";
// Repo isn't named homebrew-*, so the tap needs its explicit URL once.
export const brewTap = "brew tap jnahian/reader.md https://github.com/jnahian/reader.md";
// Trust the cask from this tap before installing.
export const brewTrust = "brew trust --cask jnahian/reader.md/reader.md";
export const brewInstall = "brew install --cask reader-md";
export const author = "Julkar Naen Nahian";
export const currentVersion = "1.10.0";

export type Page = "home" | "docs" | "changelog";

// Nav links shown per page (the current page is surfaced as a badge instead).
export const navLinksFor = (page: Page) => {
  const home = { href: "/", label: "Home" };
  const features = { href: "/#features", label: "Features" };
  const docs = { href: "/docs", label: "Docs" };
  const changelog = { href: "/changelog", label: "Changelog" };
  if (page === "docs") return [home, changelog];
  if (page === "changelog") return [home, docs];
  return [features, docs, changelog];
};

export const footerLinks = [
  { href: "/docs", label: "Docs" },
  { href: "/changelog", label: "Changelog" },
  { href: repo, label: "GitHub" },
  { href: website, label: "Website" },
];
