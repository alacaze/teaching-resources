# Load required packages
library(xml2)
library(rvest)
library(httr)
library(purrr)
library(dplyr)
library(tibble)
library(stringr)

# Set the root path to your unzipped edX export folder
# course_root <- "20250716_course" 

args <- commandArgs(trailingOnly = TRUE)

if (length(args) > 0) {
  # Grab the first argument passed from the command line
  course_root <- args[1]
  message(paste("Using command line argument for course root:", course_root))
} else {
  # Default fallback if no arguments are provided (e.g., running interactively in RStudio)
  stop("Error: Exported folder for Extend course is needed.")
}

# Verify the folder actually exists before proceeding
if (!dir.exists(course_root)) {
  stop(paste("Error: The directory '", course_root, "' does not exist. Please check the path.", sep = ""))
}

# Generate a clean output filename based on the course root name
output_filename <- paste0(basename(course_root), "_course_components_report.csv")

# =========================================================================
# 1. Parse edX XML Structural Layers & Component Types
# =========================================================================

# Standard structural mapper for high-level folders (chapter, sequential)
parse_high_layers <- function(folder_name) {
  target_dir <- file.path(course_root, folder_name)
  if (!dir.exists(target_dir)) return(tibble())
  
  files <- list.files(target_dir, full.names = TRUE, pattern = "\\.xml$")
  
  map_dfr(files, function(file_path) {
    xml_data <- tryCatch(read_xml(file_path), error = function(e) return(NULL))
    if (is.null(xml_data)) return(NULL)
    
    node_hash <- str_remove(basename(file_path), "\\.xml$")
    display_name <- xml_attr(xml_data, "display_name")
    
    children <- xml_find_all(xml_data, ".//*[@url_name]")
    child_hashes <- xml_attr(children, "url_name")
    child_hashes <- str_trim(str_remove(child_hashes, "\\.xml$|\\.html?$"))
    child_hashes <- child_hashes[!is.na(child_hashes) & child_hashes != ""]
    
    if (length(child_hashes) == 0) return(NULL)
    
    tibble(parent_hash = node_hash, parent_title = display_name, child_hash = child_hashes)
  })
}

# Special parser for Verticals to track component types AND inline LTI launch URLs
parse_verticals <- function() {
  target_dir <- file.path(course_root, "vertical")
  if (!dir.exists(target_dir)) return(tibble())
  
  files <- list.files(target_dir, full.names = TRUE, pattern = "\\.xml$")
  
  map_dfr(files, function(file_path) {
    xml_data <- tryCatch(read_xml(file_path), error = function(e) return(NULL))
    if (is.null(xml_data)) return(NULL)
    
    vert_hash <- str_remove(basename(file_path), "\\.xml$")
    vert_title <- xml_attr(xml_data, "display_name")
    
    # Find direct children of the vertical container
    children <- xml_find_all(xml_data, "/*/*")
    
    map_dfr(children, function(child) {
      comp_type <- xml_name(child) # 'html', 'problem', 'video', 'lti_consumer', etc.
      comp_hash <- xml_attr(child, "url_name")
      comp_hash <- str_trim(str_remove(comp_hash, "\\.xml$|\\.html?$"))
      
      # NEW: Directly grab the launch_url attribute from this node if it exists
      inline_launch_url <- xml_attr(child, "launch_url")
      
      if (is.na(comp_hash) || comp_hash == "") return(NULL)
      
      tibble(
        vertical_hash = vert_hash,
        unit_name = vert_title,
        component_type = comp_type,
        component_hash = comp_hash,
        launch_url = ifelse(!is.na(inline_launch_url), inline_launch_url, NA_character_)
      )
    })
  })
}

message("Step 1: Extracting structural hierarchy and element tags...")
chapters_map    <- parse_high_layers("chapter")    
sequentials_map <- parse_high_layers("sequential") 
verticals_map   <- parse_verticals()

# Match high-level titles
chapter_titles    <- chapters_map %>% select(chapter_hash = parent_hash, section_name = parent_title) %>% distinct()
sequential_titles <- sequentials_map %>% select(sequential_hash = parent_hash, subsection_name = parent_title) %>% distinct()

# Stitch the macro course timeline together
course_timeline <- chapters_map %>%
  select(chapter_hash = parent_hash, sequential_hash = child_hash) %>%
  left_join(sequentials_map %>% select(sequential_hash = parent_hash, vertical_hash = child_hash), by = "sequential_hash") %>%
  left_join(chapter_titles, by = "chapter_hash") %>%
  left_join(sequential_titles, by = "sequential_hash") %>%
  filter(!is.na(vertical_hash))

# Join timeline mapping onto our vertical component lists
full_hierarchy <- verticals_map %>%
  left_join(course_timeline, by = c("vertical_hash" = "vertical_hash")) %>%
  distinct(component_hash, .keep_all = TRUE)


# =========================================================================
# 2. Extract Specialized Data and Titles from Target Folders
# =========================================================================
message("Step 2: Processing specific component details (Problems, Videos)...")

# Helper function to grab root attributes from remaining standalone folders
get_component_meta <- function(folder_name, attribute_name = "display_name") {
  target_dir <- file.path(course_root, folder_name)
  if (!dir.exists(target_dir)) return(tibble(hash = character(), val = character()))
  
  files <- list.files(target_dir, full.names = TRUE, pattern = "\\.xml$")
  map_dfr(files, function(file_path) {
    xml_data <- tryCatch(read_xml(file_path), error = function(e) return(NULL))
    if (is.null(xml_data)) return(NULL)
    
    hash <- str_remove(basename(file_path), "\\.xml$")
    val  <- xml_attr(xml_data, attribute_name)
    
    if (is.na(val)) {
      val <- xml_attr(xml_find_first(xml_data, paste0(".//*[@", attribute_name, "]")), attribute_name)
    }
    
    tibble(hash = hash, val = as.character(val))
  })
}

# Pull structural Display Names for Problem components
problem_titles <- get_component_meta("problem", "display_name") %>% rename(prob_title = val)

# Pull YouTube IDs from Video configurations
video_dir <- file.path(course_root, "video")
video_ids <- tibble(hash = character(), yt_id = character())
if (dir.exists(video_dir)) {
  video_ids <- map_dfr(list.files(video_dir, full.names = TRUE, pattern = "\\.xml$"), function(f) {
    xml_data <- tryCatch(read_xml(f), error = function(e) return(NULL))
    if (is.null(xml_data)) return(NULL)
    yt <- xml_attr(xml_data, "youtube_id_1_0")
    if (is.na(yt) || yt == "") yt <- xml_attr(xml_find_first(xml_data, ".//video_asset"), "id")
    if (is.na(yt) || yt == "") yt <- xml_text(xml_find_first(xml_data, ".//transcripts/../@youtube_id_1_0")) 
    tibble(hash = str_remove(basename(f), "\\.xml$"), yt_id = ifelse(!is.na(yt), yt, "ID Not Found"))
  })
}


# =========================================================================
# 3. Scrape Standard Hyperlinks (HTML & Problem Files)
# =========================================================================
message("Step 3: Extracting hyperlinks from text fields...")

extract_links <- function(file_path) {
  page <- tryCatch(read_html(file_path), error = function(e) return(NULL))
  if (is.null(page)) return(tibble())
  
  file_hash <- str_remove(basename(file_path), "\\.html?$|\\.xml$")
  href_links <- html_nodes(page, xpath = '//*[@href]') %>% html_attr("href")
  src_links  <- html_nodes(page, xpath = '//*[@src]') %>% html_attr("src")
  
  links <- c(href_links, src_links)
  links <- links[!is.na(links) & links != ""]
  if (length(links) == 0) return(tibble())
  
  tibble(component_hash = file_hash, extracted_link = links)
}

html_files <- list.files(file.path(course_root, "html"), pattern = "\\.html?$", full.names = TRUE)
prob_files <- list.files(file.path(course_root, "problem"), pattern = "\\.xml$", full.names = TRUE)

content_links <- map_dfr(c(html_files, prob_files), extract_links) %>% distinct()


# =========================================================================
# 4. Synthesize Component Rules & Evaluate Links
# =========================================================================
message("Step 4: Compiling custom component rules and auditing links...")

check_link <- function(url) {
  if (!grepl("^https?://", url)) return(NA_integer_)
  tryCatch({
    resp <- HEAD(url, timeout(5), user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"))
    status_code(resp)
  }, error = function(e) NA_integer_)
}

final_report <- full_hierarchy %>%
  left_join(content_links, by = "component_hash") %>%
  left_join(problem_titles, by = c("component_hash" = "hash")) %>%
  left_join(video_ids, by = c("component_hash" = "hash")) %>%
  
  # Execute Custom Content Formatting Logic per type
  mutate(
    # Set item names contextually
    item_display_name = case_when(
      component_type == "problem"      ~ "Edx problem",
      component_type == "video"        ~ "Video Component",
      component_type == "lti_consumer" ~ "External Tool Link (LTI)",
      TRUE                             ~ "HTML Content Page"
    ),
    
    # Assign destination (Actual link, YouTube ID, or inline launch URL fetched in step 1)
    target_destination = case_when(
      component_type == "video"        ~ paste0("https://youtube.com/watch?v=", coalesce(yt_id, "Missing ID")),
      component_type == "lti_consumer" ~ paste0("LTI Launch Target: ", coalesce(launch_url, "Missing URL")),
      TRUE                             ~ extracted_link
    ),
    
    is_absolute = grepl("^https?://", target_destination),
    
    # Structural classification labels
    link_type = case_when(
      component_type == "problem" ~ coalesce(prob_title, "Unnamed Problem"),
      component_type == "video"                                            ~ "Video Embed",
      component_type == "lti_consumer"                                     ~ "LTI Tool Integrations",
      grepl("h5p", target_destination, ignore.case = TRUE)                 ~ "H5P Content",
      grepl("library\\.uq\\.edu\\.au|uq\\.edu\\.au/library", target_destination) ~ "UQ Library Resource",
      grepl("tastrax|exlibrisgroup|ezproxy|amhonline", target_destination, ignore.case = TRUE) ~ "Library Proxy/Database",
      grepl("echo360|lecture-capture", target_destination, ignore.case = TRUE) ~ "Echo360 Video Link",
      grepl("^/static/", target_destination)                               ~ "Internal edX Asset (Static)",
      !is_absolute & !is.na(target_destination)                            ~ "Relative Layout Path",
      is_absolute                                                          ~ "External Web Link",
      TRUE                                                                 ~ "No Links Present"
    ),
    
    # Evaluate live link check status where applicable
    status = ifelse(is_absolute & component_type %in% c("html", "problem"), 
                    map_int(target_destination, check_link), NA_integer_)
  ) %>%
  
  # Fill structure missing flags
  mutate(
    section_name    = coalesce(section_name, "Unlinked Assets / Include Folders"),
    subsection_name = coalesce(subsection_name, "-"),
    unit_name       = coalesce(unit_name, paste0("Component: ", component_hash))
  ) %>%
  
  # Select final tabular layout columns
  select(section_name, subsection_name, unit_name, item_display_name, link_type, target_destination, status) %>%
  arrange(section_name, subsection_name, unit_name)

# Export complete summary matrix
write.csv(final_report, output_filename, row.names = FALSE)
message(paste("Success! Report saved to", output_filename, sep = ""))