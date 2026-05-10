const albums = Array.isArray(window.GALLERY_DATA) ? window.GALLERY_DATA : [];

const homeView = document.getElementById("homeView");
const galleryView = document.getElementById("galleryView");
const albumList = document.getElementById("albumList");
const todayLabel = document.getElementById("todayLabel");
const galleryTitle = document.getElementById("galleryTitle");
const galleryDate = document.getElementById("galleryDate");
const galleryGrid = document.getElementById("galleryGrid");
const backButton = document.getElementById("backButton");
const lightbox = document.getElementById("lightbox");
const lightboxMedia = document.getElementById("lightboxMedia");
const closeLightboxButton = document.getElementById("closeLightbox");
const prevMediaButton = document.getElementById("prevMedia");
const nextMediaButton = document.getElementById("nextMedia");

const albumMap = new Map(albums.map((album) => [album.id, album]));
const galleryBatchSize = 18;
const galleryLoadSentinel = document.createElement("div");

let activeAlbumId = null;
let activeMediaIndex = 0;
let albumScrollTop = 0;
let touchStartX = 0;
let renderedMediaCount = 0;

galleryLoadSentinel.className = "gallery-load-sentinel";

const batchObserver = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting || !activeAlbumId) {
          return;
        }

        renderNextMediaBatch();
      });
    }, { rootMargin: "240px 0px" })
  : null;

todayLabel.textContent = formatChineseDate(new Date());

renderAlbumList();
syncRoute();

window.addEventListener("hashchange", syncRoute);
backButton.addEventListener("click", () => {
  location.hash = "";
});

closeLightboxButton.addEventListener("click", closeLightbox);
prevMediaButton.addEventListener("click", () => stepLightbox(-1));
nextMediaButton.addEventListener("click", () => stepLightbox(1));

lightbox.addEventListener("click", (event) => {
  const target = event.target;
  if (target instanceof HTMLElement && target.dataset.closeLightbox === "true") {
    closeLightbox();
  }
});

document.addEventListener("keydown", (event) => {
  if (!isLightboxOpen()) {
    if (event.key === "Escape" && activeAlbumId) {
      location.hash = "";
    }
    return;
  }

  if (event.key === "Escape") {
    closeLightbox();
  } else if (event.key === "ArrowLeft") {
    stepLightbox(-1);
  } else if (event.key === "ArrowRight") {
    stepLightbox(1);
  }
});

lightbox.addEventListener(
  "touchstart",
  (event) => {
    touchStartX = event.changedTouches[0].clientX;
  },
  { passive: true }
);

lightbox.addEventListener(
  "touchend",
  (event) => {
    const deltaX = event.changedTouches[0].clientX - touchStartX;
    if (Math.abs(deltaX) < 50) {
      return;
    }

    if (deltaX > 0) {
      stepLightbox(-1);
    } else {
      stepLightbox(1);
    }
  },
  { passive: true }
);

function renderAlbumList() {
  if (!albums.length) {
    albumList.innerHTML = '<div class="empty-state">没有读取到可展示的相册数据。</div>';
    return;
  }

  const fragment = document.createDocumentFragment();

  albums.forEach((album, index) => {
    const entry = document.createElement("button");
    entry.type = "button";
    entry.className = "timeline-entry";
    entry.style.setProperty("--delay", `${index * 36}ms`);
    entry.dataset.albumId = album.id;
    entry.innerHTML = `
      <p class="timeline-entry-date">${getAlbumDisplayDate(album)}</p>
      <h3 class="timeline-entry-place">${album.location}</h3>
    `;
    fragment.appendChild(entry);
  });

  albumList.replaceChildren(fragment);
}

albumList.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  const entry = target.closest(".timeline-entry");
  if (!(entry instanceof HTMLElement)) {
    return;
  }

  const { albumId } = entry.dataset;
  if (!albumId) {
    return;
  }

  openAlbum(albumId);
});

function openAlbum(albumId) {
  const targetHash = getAlbumHash(albumId);
  if (location.hash !== targetHash) {
    location.hash = targetHash;
    return;
  }

  showAlbum(albumId);
}

function syncRoute() {
  const albumId = parseAlbumHash(location.hash);
  if (albumId && albumMap.has(albumId)) {
    showAlbum(albumId);
    return;
  }

  showHome();
}

function showAlbum(albumId) {
  const album = albumMap.get(albumId);
  if (!album) {
    showHome();
    return;
  }

  if (!activeAlbumId) {
    albumScrollTop = window.scrollY;
  }

  activeAlbumId = albumId;
  renderGallery(album);
  switchView(galleryView, homeView);
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function showHome() {
  activeAlbumId = null;
  renderedMediaCount = 0;
  if (batchObserver) {
    batchObserver.disconnect();
  }
  closeLightbox(true);
  switchView(homeView, galleryView);
  window.scrollTo({ top: albumScrollTop, behavior: "smooth" });
}

function renderGallery(album) {
  galleryDate.textContent = getAlbumDisplayDate(album);
  galleryTitle.textContent = album.location;
  renderedMediaCount = 0;

  if (batchObserver) {
    batchObserver.disconnect();
  }

  if (!album.media.length) {
    galleryGrid.innerHTML = '<div class="empty-state">这个相册里暂时没有内容。</div>';
    return;
  }

  galleryGrid.replaceChildren();
  renderNextMediaBatch();
}

function renderNextMediaBatch() {
  const album = albumMap.get(activeAlbumId);
  if (!album || renderedMediaCount >= album.media.length) {
    if (batchObserver) {
      batchObserver.disconnect();
    }
    galleryLoadSentinel.remove();
    return;
  }

  const nextItems = album.media.slice(renderedMediaCount, renderedMediaCount + galleryBatchSize);
  const fragment = document.createDocumentFragment();

  nextItems.forEach((item, offset) => {
    const index = renderedMediaCount + offset;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "media-card";
    button.setAttribute("aria-label", `查看第 ${index + 1} 张`);
    button.appendChild(renderMediaPreview(item, `${album.location} 第 ${index + 1} 张`, index < 4));
    button.addEventListener("click", () => openLightbox(index));
    fragment.appendChild(button);
  });

  galleryGrid.appendChild(fragment);
  renderedMediaCount += nextItems.length;

  if (renderedMediaCount < album.media.length) {
    galleryGrid.appendChild(galleryLoadSentinel);
    if (batchObserver) {
      batchObserver.disconnect();
      batchObserver.observe(galleryLoadSentinel);
    }
  } else {
    galleryLoadSentinel.remove();
  }
}

function renderMediaPreview(item, altText, eager) {
  if (item.type === "video") {
    const video = document.createElement("video");
    video.src = toAssetUrl(item.src);
    video.muted = true;
    video.playsInline = true;
    video.preload = eager ? "metadata" : "none";
    return video;
  }

  const image = document.createElement("img");
  image.src = toAssetUrl(item.thumb || item.src);
  image.alt = altText;
  image.loading = eager ? "eager" : "lazy";
  image.decoding = "async";
  if (!eager) {
    image.fetchPriority = "low";
  }
  return image;
}

function openLightbox(index) {
  if (!activeAlbumId) {
    return;
  }

  activeMediaIndex = index;
  renderLightbox();
  lightbox.classList.add("is-open");
  lightbox.setAttribute("aria-hidden", "false");
  document.body.style.overflow = "hidden";
}

function closeLightbox(force = false) {
  if (!force && !isLightboxOpen()) {
    return;
  }

  lightbox.classList.remove("is-open");
  lightbox.setAttribute("aria-hidden", "true");
  lightboxMedia.replaceChildren();
  document.body.style.overflow = "";
}

function stepLightbox(step) {
  const album = albumMap.get(activeAlbumId);
  if (!album || !album.media.length) {
    return;
  }

  activeMediaIndex = (activeMediaIndex + step + album.media.length) % album.media.length;
  renderLightbox();
}

function renderLightbox() {
  const album = albumMap.get(activeAlbumId);
  if (!album) {
    return;
  }

  const item = album.media[activeMediaIndex];
  lightboxMedia.replaceChildren();

  if (item.type === "video") {
    const video = document.createElement("video");
    video.src = toAssetUrl(item.src);
    video.controls = true;
    video.autoplay = true;
    video.playsInline = true;
    lightboxMedia.appendChild(video);
    return;
  }

  const frame = document.createElement("div");
  frame.className = "lightbox-image-frame is-loading";

  const preview = document.createElement("img");
  preview.className = "lightbox-preview-image";
  preview.src = toAssetUrl(item.thumb || item.src);
  preview.alt = `${album.location} 第 ${activeMediaIndex + 1} 张`;
  preview.decoding = "async";
  frame.appendChild(preview);

  const status = document.createElement("div");
  status.className = "lightbox-status";
  status.textContent = "正在加载原图…";
  frame.appendChild(status);

  const original = new Image();
  original.className = "lightbox-full-image";
  original.alt = preview.alt;
  original.decoding = "async";

  original.addEventListener("load", () => {
    if (frame.parentElement !== lightboxMedia) {
      return;
    }

    frame.appendChild(original);
    frame.classList.remove("is-loading");
    frame.classList.add("is-ready");
    status.remove();
  });

  original.addEventListener("error", () => {
    if (frame.parentElement !== lightboxMedia) {
      return;
    }

    frame.classList.remove("is-loading");
    frame.classList.add("has-error");
    status.textContent = "原图加载失败，当前显示缩略图";
  });

  lightboxMedia.appendChild(frame);
  original.src = toAssetUrl(item.src);
}

function switchView(nextView, prevView) {
  if (nextView === prevView || nextView.classList.contains("is-active")) {
    return;
  }

  const apply = () => {
    prevView.classList.remove("is-active");
    prevView.hidden = true;
    nextView.hidden = false;
    nextView.classList.add("is-active");
  };

  if (document.startViewTransition) {
    document.startViewTransition(apply);
  } else {
    apply();
  }
}

function getAlbumDisplayDate(album) {
  if (album.year && album.month && album.day) {
    return `${album.year}年${album.month}月${album.day}日`;
  }

  if (typeof album.displayDate === "string" && /^\d{8}$/.test(album.displayDate)) {
    return `${album.displayDate.slice(0, 4)}年${Number(album.displayDate.slice(4, 6))}月${Number(album.displayDate.slice(6, 8))}日`;
  }

  return album.displayDate || "未标注日期";
}

function formatChineseDate(value) {
  const date = value instanceof Date ? value : new Date(value);
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

function getAlbumHash(albumId) {
  return `#album=${encodeURIComponent(albumId)}`;
}

function parseAlbumHash(hash) {
  if (!hash.startsWith("#album=")) {
    return "";
  }

  try {
    return decodeURIComponent(hash.slice(7));
  } catch {
    return "";
  }
}

function toAssetUrl(path) {
  if (typeof path !== "string" || !path) {
    return "";
  }

  return path
    .split("/")
    .map((segment, index) => (index === 0 && segment === "." ? "." : encodeURIComponent(segment)))
    .join("/")
    .replace(".%2F", "./");
}

function isLightboxOpen() {
  return lightbox.classList.contains("is-open");
}
