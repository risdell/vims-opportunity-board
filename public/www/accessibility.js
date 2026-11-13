/* Opportunity Board accessibility enhancements.
   Keep this JS small: it supports the existing R/Shiny form validation and
   adds a skip link that follows whichever navigation tab is active. */
(function () {
  "use strict";

  var formFields = {
    submit: [
      "submit_name", "submit_department", "submit_contact_name",
      "submit_contact_email", "submit_description", "submit_application_url",
      "submit_start_date", "submit_end_date",
      "submit_deadline", "submit_expiration"
    ],
    request: ["request_title", "request_opportunity", "request_email", "request_details"]
  };

  function controlFor(id) {
    var node = document.getElementById(id);
    if (!node) return null;
    if (node.matches && node.matches("input, select, textarea")) return node;
    return node.querySelector("input:not([type=hidden]), select, textarea") ||
      node.querySelector("input, select, textarea") || null;
  }

  function visibleMain() {
    return document.querySelector(".tab-pane.active main") ||
      Array.prototype.find.call(document.querySelectorAll("main"), function (node) {
        return node.getClientRects().length > 0;
      });
  }

  function addSkipLink() {
    if (document.querySelector(".oppboard-skip-link")) return;
    var link = document.createElement("a");
    link.className = "oppboard-skip-link";
    link.href = "#browse-main";
    link.textContent = "Skip to main content";
    link.addEventListener("click", function (event) {
      var main = visibleMain();
      if (!main) return;
      event.preventDefault();
      main.setAttribute("tabindex", "-1");
      main.focus({ preventScroll: true });
      main.scrollIntoView({ block: "start" });
    });
    document.body.insertBefore(link, document.body.firstChild);
  }

  function markRequiredFields() {
    formFields.submit.filter(function (id) { return id !== "submit_application_url"; })
      .forEach(function (id) {
      var input = controlFor(id);
      if (input) input.setAttribute("aria-required", "true");
    });
    ["request_email", "request_details"].forEach(function (id) {
      var input = controlFor(id);
      if (input) input.setAttribute("aria-required", "true");
    });
  }

  function restoreControl(input) {
    if (!input) return;
    input.removeAttribute("aria-invalid");
    if (input.dataset.oppboardOriginalDescription !== undefined) {
      var former = input.dataset.oppboardOriginalDescription;
      if (former) input.setAttribute("aria-describedby", former);
      else input.removeAttribute("aria-describedby");
      delete input.dataset.oppboardOriginalDescription;
    }
  }

  function showFormErrors(data) {
    if (!data || !formFields[data.form]) return;
    var region = document.getElementById(data.form + "-errors");
    if (!region) return;

    formFields[data.form].forEach(function (id) {
      var input = controlFor(id);
      restoreControl(input);
      var prior = document.getElementById(id + "-accessibility-error");
      if (prior) prior.remove();
    });
    region.replaceChildren();

    var errors = Array.isArray(data.errors) ? data.errors : [];
    if (!errors.length) return;

    var heading = document.createElement("p");
    heading.className = "form-error-heading";
    heading.textContent = "Please correct " + errors.length +
      (errors.length === 1 ? " field:" : " fields:");
    region.appendChild(heading);
    var list = document.createElement("ul");
    list.className = "form-error-list";

    errors.forEach(function (entry) {
      if (!entry || typeof entry.id !== "string" || typeof entry.message !== "string") return;
      var input = controlFor(entry.id);
      var li = document.createElement("li");
      if (input) {
        var anchor = document.createElement("a");
        anchor.href = "#" + entry.id;
        anchor.textContent = entry.message;
        anchor.addEventListener("click", function (event) {
          event.preventDefault();
          input.focus();
          input.scrollIntoView({ block: "center" });
        });
        li.appendChild(anchor);

        input.setAttribute("aria-invalid", "true");
        if (input.dataset.oppboardOriginalDescription === undefined) {
          input.dataset.oppboardOriginalDescription = input.getAttribute("aria-describedby") || "";
        }
        var errorId = entry.id + "-accessibility-error";
        var described = [input.dataset.oppboardOriginalDescription, errorId]
          .filter(Boolean).join(" ");
        input.setAttribute("aria-describedby", described);

        var message = document.createElement("p");
        message.id = errorId;
        message.className = "field-error";
        message.textContent = entry.message;
        var wrapper = input.closest(".shiny-input-container") || input.parentElement;
        if (wrapper) wrapper.appendChild(message);
      } else {
        li.textContent = entry.message;
      }
      list.appendChild(li);
    });
    region.appendChild(list);
    window.requestAnimationFrame(function () {
      region.focus();
      region.scrollIntoView({ block: "center" });
    });
  }

  var handlerRegistered = false;
  function registerHandler() {
    if (handlerRegistered || !window.Shiny ||
        typeof window.Shiny.addCustomMessageHandler !== "function") return;
    window.Shiny.addCustomMessageHandler("opportunity-form-errors", showFormErrors);
    handlerRegistered = true;
  }

  function boot() {
    addSkipLink();
    markRequiredFields();
    registerHandler();
    if (window.jQuery) {
      window.jQuery(document).on("shiny:connected", registerHandler);
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
