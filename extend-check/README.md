# Extend Course Component Map & Link Checker

>[NOTE!]
>The most of the script and these notes have been by Gemini output.

An automation script written in R designed to parse unzipped edX course export archives. It extracts full course lineage (Sections, Subsections, and Units), maps content types, and systematically validates embedded hyperlinks across HTML content pages and quizzes.

## Features

* **Hierarchical Layout Mapping:** Automatically builds structural lineages directly from your course files, linking items chronologically (**Section $\rightarrow$ Subsection $\rightarrow$ Unit**).
* **Targeted Component Isolation:** Automatically scans `vertical/` declarations to isolate and handle specific components:
* **HTML Pages:** Scraped for standard hyperlinks (`href` and `src`).
* **Edx Problems:** Identifies quiz/assessment elements, classifies them by their human-readable item titles (`link_type`), and safely sweeps problem XML structures for embedded links.
* **Video Embeds:** Bypasses missing file layers to extract and report specific YouTube ID strings.
* **LTI Tool Integrations:** Captures and prints inline `launch_url` external parameters to the spreadsheet.
* **Smart Link Classification:** Categorizes destinations dynamically into explicit categories such as **H5P Content**, **UQ Library Resources**, **Library Proxy/Databases (e.g., AMH, EZproxy)**, **Echo360 Video Links**, and internal course paths.
* **Live Auditing Engine:** Performs automated asynchronous `HEAD` requests to verify live destination URLs, capturing server status codes (e.g., `200`, `404`) while using a custom user-agent to prevent false security blocks.




## Output Architecture

The script generates a cleanly structured CSV spreadsheet named `[Your_Course_Folder]_course_components_report.csv` containing the following columns:

| Column Name | Description |
| --- | --- |
| `section_name` | The highest-level module header (e.g., *Week 1 Introduction*). |
| `subsection_name` | The mid-level course subsection (e.g., *Required Learning Modules*). |
| `unit_name` | The individual unit page name containing the element. |
| `item_display_name` | Explicit component indicator (`HTML Content Page`, `Edx Problem`, `Video Component`, `External Tool Link (LTI)`). |
| `link_type` | Categorized URL types, **or the true title of the quiz question if the row is an Edx Problem**. |
| `target_destination` | The checked URL string, the inline LTI endpoint, or the embedded YouTube Asset ID. |
| `status` | The HTTP live status response code (e.g., `200` = OK; `404` = Broken). |



## Intended use

The idea is that you can use the spreadsheet to identify and review course components, e.g.:

* Filter `status` to identify dead links via the [HTTP status code](https://en.wikipedia.org/wiki/List_of_HTTP_status_codes); for example `200` means the link is fine; `404` is a dead link; `403` typically means that some authenication is required prior to access
* Filter `item_display_name` to
	* Find all video components in the course and the associated youtube id/link
	* Find and review Edx Problems
* H5P content can be found in more than one place depending on how it has been embedded into the course
	* `link_type`: "H5P Content" or
	* `item_display_name`: "External Tool Link"
* Review static resource links via `link_type`: "External edX Asset (Static)"

Filtering for the content you want and then working back along the row will identify the Section/Subsection/Unit that contains the component.

## Prerequisites

Ensure you have R installed on your system along with the following mandatory packages:

```R
install.packages(c("xml2", "rvest", "httr", "purrr", "dplyr", "tibble", "stringr"))

```

---

## Usage

### 1. Preparation

Place your unzipped edX export archive folder (containing subfolders like `chapter`, `sequential`, `vertical`, `html`, and `problem`) inside your active working directory.

### 2. Execution via Terminal / Command Line

Run the script through your command line terminal by passing the unzipped folder's name as an argument:

```bash
Rscript extend-check.R 20251217_PHRM3101

```

> [NOTE!]
> If no arguments are passed, the script will provide an error message and stop execution

