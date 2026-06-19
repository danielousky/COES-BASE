// Entry point for the build script in your package.json

import "@hotwired/turbo-rails";
import "./controllers"; // Stimulus (controllers compartidos: enrollment, etc.)

import jquery from 'jquery';
window.jQuery = jquery;
window.$ = jquery;

import * as toastr from "toastr";
window.toastr = toastr;
import * as bootstrap from 'bootstrap';
window.bootstrap = bootstrap;

// import "./eduport/eduport";
// import "./eduport/functions";



/* For Rich Tech in Billboards */
import "trix"
import "@rails/actiontext"

var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
var tooltipList = tooltipTriggerList.map(function(tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl)
})

var popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'))
var popoverList = popoverTriggerList.map(function(popoverTriggerEl) {
    return new bootstrap.Popover(popoverTriggerEl)
})