const slides = Array.from(document.querySelectorAll(".slide"));
const prevButton = document.querySelector("#prev");
const nextButton = document.querySelector("#next");
const printButton = document.querySelector("#print");
const counter = document.querySelector("#counter");
const dots = document.querySelector(".slide-dots");
const imageZoom = document.querySelector("#imageZoom");
const imageZoomImg = imageZoom.querySelector("img");
const zoomCloseButton = imageZoom.querySelector(".zoom-close");

let activeIndex = 0;

function renderDots() {
  dots.innerHTML = "";
  slides.forEach((slide, index) => {
    const dot = document.createElement("button");
    dot.type = "button";
    dot.title = slide.dataset.title || `Slide ${index + 1}`;
    dot.setAttribute("aria-label", `Go to ${dot.title}`);
    dot.addEventListener("click", () => showSlide(index));
    dots.appendChild(dot);
  });
}

function showSlide(index) {
  activeIndex = Math.max(0, Math.min(index, slides.length - 1));
  slides.forEach((slide, slideIndex) => {
    slide.classList.toggle("active", slideIndex === activeIndex);
  });
  Array.from(dots.children).forEach((dot, dotIndex) => {
    dot.classList.toggle("active", dotIndex === activeIndex);
  });
  counter.textContent = `${activeIndex + 1} / ${slides.length}`;
  prevButton.disabled = activeIndex === 0;
  nextButton.disabled = activeIndex === slides.length - 1;
}

prevButton.addEventListener("click", () => showSlide(activeIndex - 1));
nextButton.addEventListener("click", () => showSlide(activeIndex + 1));

const PDF_PAGE_WIDTH = 1280;
const PDF_PAGE_HEIGHT = 720;

function preparePrintView(capturing = false) {
  document.body.classList.add("is-printing");
  if (capturing) {
    document.body.classList.add("pdf-capturing");
  }
  slides.forEach((slide) => {
    slide.classList.add("active");
    slide.style.animation = "none";
  });
}

function cleanupPrintView(restoreIndex) {
  document.body.classList.remove("is-printing", "pdf-capturing");
  slides.forEach((slide) => {
    slide.classList.remove("print-page");
    slide.style.animation = "";
  });
  if (typeof restoreIndex === "number") {
    showSlide(restoreIndex);
  } else {
    showSlide(activeIndex);
  }
}

function waitForImages(root) {
  const images = Array.from(root.querySelectorAll("img"));
  return Promise.all(
    images.map(
      (image) =>
        new Promise((resolve) => {
          if (image.complete) {
            resolve();
            return;
          }
          image.addEventListener("load", resolve, { once: true });
          image.addEventListener("error", resolve, { once: true });
        }),
    ),
  );
}

async function downloadPresentationPdf() {
  if (typeof html2canvas === "undefined" || !window.jspdf) {
    preparePrintView();
    window.print();
    return;
  }

  const previousIndex = activeIndex;
  const originalLabel = printButton.textContent;
  printButton.disabled = true;
  printButton.textContent = "Generating PDF...";

  try {
    preparePrintView(true);
    await waitForImages(document.querySelector(".deck"));
    await new Promise((resolve) => requestAnimationFrame(resolve));

    const { jsPDF } = window.jspdf;
    const pdf = new jsPDF({
      orientation: "landscape",
      unit: "mm",
      format: "a4",
      compress: true,
    });
    const pageWidth = pdf.internal.pageSize.getWidth();
    const pageHeight = pdf.internal.pageSize.getHeight();

    for (let index = 0; index < slides.length; index += 1) {
      slides.forEach((slide, slideIndex) => {
        slide.classList.toggle("print-page", slideIndex === index);
      });

      await new Promise((resolve) => requestAnimationFrame(resolve));

      const canvas = await html2canvas(slides[index], {
        scale: 2,
        useCORS: true,
        allowTaint: true,
        backgroundColor: null,
        logging: false,
        width: PDF_PAGE_WIDTH,
        height: PDF_PAGE_HEIGHT,
        windowWidth: PDF_PAGE_WIDTH,
        windowHeight: PDF_PAGE_HEIGHT,
      });

      const imageData = canvas.toDataURL("image/jpeg", 0.95);
      if (index > 0) {
        pdf.addPage();
      }
      pdf.addImage(imageData, "JPEG", 0, 0, pageWidth, pageHeight, undefined, "FAST");
    }

    pdf.save("SalesFlow-CRM-Presentation.pdf");
  } catch (error) {
    console.error("PDF generation failed:", error);
    alert("PDF download failed. Please try again or use browser print.");
  } finally {
    cleanupPrintView(previousIndex);
    printButton.disabled = false;
    printButton.textContent = originalLabel;
  }
}

window.addEventListener("beforeprint", preparePrintView);
window.addEventListener("afterprint", cleanupPrintView);

printButton.addEventListener("click", downloadPresentationPdf);

function openImageZoom(image) {
  imageZoomImg.src = image.currentSrc || image.src;
  imageZoomImg.alt = image.alt || "Zoomed presentation image";
  imageZoom.classList.add("open");
  imageZoom.setAttribute("aria-hidden", "false");
  zoomCloseButton.focus();
}

function closeImageZoom() {
  imageZoom.classList.remove("open");
  imageZoom.setAttribute("aria-hidden", "true");
  imageZoomImg.src = "";
}

document.querySelectorAll(".screenshot-frame img, .illustration-frame img").forEach((image) => {
  image.addEventListener("click", () => openImageZoom(image));
});

imageZoom.addEventListener("click", (event) => {
  if (event.target === imageZoom || event.target === imageZoomImg) {
    closeImageZoom();
  }
});

zoomCloseButton.addEventListener("click", closeImageZoom);

document.addEventListener("keydown", (event) => {
  if (imageZoom.classList.contains("open")) {
    if (event.key === "Escape" || event.key === " " || event.key === "Enter") {
      event.preventDefault();
      closeImageZoom();
    }
    return;
  }

  if (event.key === "ArrowRight" || event.key === "PageDown" || event.key === " ") {
    event.preventDefault();
    showSlide(activeIndex + 1);
  }
  if (event.key === "ArrowLeft" || event.key === "PageUp") {
    event.preventDefault();
    showSlide(activeIndex - 1);
  }
  if (event.key === "Home") {
    event.preventDefault();
    showSlide(0);
  }
  if (event.key === "End") {
    event.preventDefault();
    showSlide(slides.length - 1);
  }
});

renderDots();
showSlide(0);
