import { useState } from "react";

const githubUrl = "https://github.com/Jazztinn/pipo";
const siteUrl = "https://pipo.jazztinn.me";

function AppleMark() {
  return <span className="mobile-apple-mark" aria-hidden="true">&#63743;</span>;
}

function MobileSite() {
  const [shareStatus, setShareStatus] = useState("");

  const shareDesktopLink = async () => {
    try {
      if (navigator.share) {
        await navigator.share({
          title: "Pipo",
          text: "Open Pipo on a desktop to try the live demo.",
          url: siteUrl,
        });
        setShareStatus("Link shared.");
      } else {
        await navigator.clipboard.writeText(siteUrl);
        setShareStatus("Link copied.");
      }
    } catch (error) {
      if (error?.name !== "AbortError") setShareStatus("Couldn’t share link.");
    }
  };

  return (
    <div className="mobile-site">
      <a className="mobile-skip-link" href="#mobile-main">Skip to content</a>

      <header className="mobile-header">
        <a className="mobile-brand" href="#mobile-top" aria-label="Pipo home">
          <img src="./pipo-logo.png" alt="" width="34" height="34" />
          <strong>pipo</strong>
        </a>
        <a className="mobile-header-link" href={githubUrl}>GitHub <span aria-hidden="true">↗</span></a>
      </header>

      <main id="mobile-main" className="mobile-main">
        <section className="mobile-landing" id="mobile-top" aria-labelledby="mobile-hero-title">
          <div className="mobile-hero">
            <img className="mobile-app-icon" src="./pipo-hero-logo.png" alt="Pipo app icon" width="168" height="168" />
            <h1 id="mobile-hero-title">Your LMS<br /><span>meets <img className="mobile-macos-wordmark" src="./macos-wordmark.png" alt="macOS" /></span></h1>
            <p className="mobile-hero-copy">Courses, deadlines, and announcements stay one click away from your Mac menu bar.</p>
            <a className="mobile-primary-button" href={githubUrl}>
              <AppleMark /> View latest Mac release
            </a>
            <p className="mobile-platform-note">Requires macOS 14 or later</p>
          </div>

          <aside className="mobile-desktop-notice" aria-labelledby="mobile-notice-title">
            <div>
              <h2 id="mobile-notice-title">Live demo available on desktop.</h2>
              <p>Open this website on your Mac or desktop for the full interactive experience.</p>
              <button type="button" onClick={shareDesktopLink}>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 16V4m0 0L7 9m5-5 5 5M5 13v5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-5" /></svg>
                Share desktop link
              </button>
              <span className="mobile-share-status" role="status" aria-live="polite">{shareStatus}</span>
            </div>
          </aside>
        </section>
      </main>
    </div>
  );
}

export { MobileSite };
