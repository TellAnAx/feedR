# =============================================================================
# report.R - PDF report of a formulation
#
# The report is drawn with R's built-in pdf() device and grid graphics
# (tables via gridExtra), so no LaTeX installation is needed on the server.
#
# Two steps:
#   new_formulation_report()   - snapshot of all inputs and the result, taken
#                                when "Formulate" is clicked (so the report
#                                always matches the displayed solution, even
#                                if inputs are edited afterwards)
#   write_formulation_report() - draws that snapshot into a PDF file
# =============================================================================


# Snapshot ----------------------------------------------------------------------

#' Collect everything the report shows
#'
#' @param result list returned by formulate_feed().
#' @param ingredients data.frame of the ingredients used (columns `label_col`,
#'   `nutrients` and optionally `cost`, `min_inclusion`, `max_inclusion`).
#' @param label_col name of the column identifying the ingredients.
#' @param tab name of the app tab the formulation was made on.
#' @param data_source short description of where the ingredient data came
#'   from (e.g. the uploaded file name), or NULL.
#' @param nutrients,nutrient_labels nutrient columns and their display names
#'   (as passed to formulate_feed()).
#' @return a list of class "formulation_report".
new_formulation_report <- function(result, ingredients, label_col, tab,
                                   data_source = NULL,
                                   nutrients = NUTRIENTS,
                                   nutrient_labels = NUTRIENT_LABELS[nutrients]) {
  optional <- function(col) {
    if (col %in% names(ingredients)) ingredients[[col]] else rep(NA_real_, nrow(ingredients))
  }
  structure(
    list(
      tab = tab,
      data_source = data_source,
      created = Sys.time(),
      result = result,
      ingredients = data.frame(
        label = ingredients[[label_col]],
        ingredients[, nutrients, drop = FALSE],
        cost = optional("cost"),
        min_inclusion = optional("min_inclusion"),
        max_inclusion = optional("max_inclusion"),
        check.names = FALSE
      ),
      label_title = if (label_col == "category1") "Category" else "Ingredient",
      nutrients = nutrients,
      nutrient_labels = unname(nutrient_labels)
    ),
    class = "formulation_report"
  )
}


#' File name for a downloaded report, e.g. "feedR_report_full_2026-09-24_1455.pdf".
report_file_name <- function(report) {
  sprintf("feedR_report_%s_%s.pdf", tolower(report$tab),
          format(report$created, "%Y-%m-%d_%H%M"))
}


# Tables shown in the report ------------------------------------------------------

# Formats numbers for tables; NA becomes "-"
fmt_cell <- function(x, digits = 2) {
  ifelse(is.na(x), "-", formatC(x, format = "f", digits = digits))
}

#' Table of the calculated mix: one row per ingredient, largest first.
report_mix_table <- function(report) {
  result <- report$result
  order <- order(result$inclusion, decreasing = TRUE)
  inclusion <- result$inclusion[order]
  notes <- trimws(gsub("[][]", "", inclusion_limit_notes(
    inclusion, result$inclusion_min[order], result$inclusion_max[order]
  )))
  cost <- report$ingredients$cost[order]
  table <- data.frame(
    ingredient = names(inclusion),
    inclusion = fmt_cell(100 * inclusion),
    cost = fmt_cell(cost * inclusion, digits = 3),
    limits = ifelse(notes == "", "-", notes)
  )
  names(table) <- c(report$label_title, "Inclusion (%)", "Cost share (per kg)", "Inclusion limits")
  total <- data.frame("Total", fmt_cell(100 * sum(inclusion)),
                      fmt_cell(result$total_cost, digits = 3), "")
  names(total) <- names(table)
  rbind(table, total)
}

#' Table of targets and, for a feasible result, the achieved composition.
report_nutrient_table <- function(report) {
  result <- report$result
  ranged <- !is.na(result$maxima)
  table <- data.frame(
    nutrient = result$labels,
    target = fmt_cell(result$targets),
    maximum = fmt_cell(result$maxima)
  )
  names(table) <- c("Nutrient", "Target / minimum", "Maximum")
  if (result$feasible) {
    difference <- fmt_cell(round(result$achieved - result$targets, 2) + 0)
    difference[ranged] <- "in range"
    table$Achieved <- fmt_cell(result$achieved)
    table$Difference <- difference
  }
  table
}

#' Table of all ingredient inputs: nutrient values, cost and inclusion limits.
report_ingredient_table <- function(report) {
  data <- report$ingredients
  table <- data.frame(label = data$label, check.names = FALSE)
  for (i in seq_along(report$nutrients)) {
    table[[report$nutrient_labels[i]]] <- fmt_cell(data[[report$nutrients[i]]])
  }
  table[["Cost (per kg)"]] <- fmt_cell(data$cost, digits = 3)
  table[["Min. incl. (%)"]] <- fmt_cell(data$min_inclusion)
  table[["Max. incl. (%)"]] <- fmt_cell(data$max_inclusion)
  names(table)[1] <- report$label_title
  table
}

#' Summary lines of the result shown below the report header.
report_summary_lines <- function(report) {
  result <- report$result
  mode <- if (result$mode == "least_cost") {
    "Least-cost formulation (cheapest mix meeting all minimums and ranges)"
  } else {
    "Target matching (mix with the smallest total deviation from the targets)"
  }
  status <- if (result$feasible) {
    c(
      "Result: optimal solution found.",
      if (result$mode == "target_matching") {
        sprintf("Total absolute deviation from targets: %.2f", result$objective)
      },
      if (is.na(result$total_cost)) {
        "Cost of the mix: not available (costs missing for some ingredients)."
      } else {
        sprintf("Cost of the mix: %.3f per kg (%.2f per 100 kg)",
                result$total_cost, 100 * result$total_cost)
      }
    )
  } else {
    "Result: no feasible solution found (see explanation below)."
  }
  c(
    paste("Tab:", report$tab),
    if (!is.null(report$data_source)) paste("Ingredient data:", report$data_source),
    paste("Mode:", mode),
    status
  )
}


# Drawing -------------------------------------------------------------------------

REPORT_PAGE <- list(width = 8.27, height = 11.69, margin = 0.7)  # A4, inches

#' Keep hyphens as hyphens in the PDF
#'
#' R's pdf() device draws "-" as a minus sign (see ?postscript), so dates
#' like 2026-09-24 and names like "non-dehulled" look wrong. A "-" directly
#' after a non-space character is replaced by the soft hyphen U+00AD, which
#' the device draws as a hyphen; leading minus signs of numbers are kept.
pdf_text <- function(x) gsub("([^[:space:](])-", "\\1\u00ad", x)

# Text block: one or more lines, left-aligned, wrapped to `wrap` characters
text_grob <- function(lines, fontsize = 9, fontface = "plain", wrap = 110) {
  wrapped <- unlist(lapply(lines, function(line) {
    if (line == "") "" else strwrap(line, width = wrap, exdent = 2)
  }))
  textGrob(pdf_text(paste(wrapped, collapse = "\n")), x = 0, y = 1, hjust = 0, vjust = 1,
           gp = gpar(fontsize = fontsize, fontface = fontface, lineheight = 1.25))
}

# Table grob that fits the page width: the font is reduced until it fits
# (down to 6 pt). The first column is left-aligned, the others right-aligned.
table_grob <- function(table, max_width) {
  # Long labels (e.g. database ingredient names) are wrapped onto two lines
  table[[1]] <- vapply(table[[1]], function(x) paste(strwrap(x, 34), collapse = "\n"),
                       character(1))
  table[] <- lapply(table, pdf_text)
  names(table) <- pdf_text(names(table))
  n <- nrow(table)
  for (size in c(8, 7, 6)) {
    theme <- gridExtra::ttheme_default(
      base_size = size,
      padding = unit(c(4, 3), "mm"),
      core = list(fg_params = list(hjust = rep(c(0, rep(1, ncol(table) - 1)), each = n),
                                   x = rep(c(0.03, rep(0.97, ncol(table) - 1)), each = n))),
      colhead = list(fg_params = list(hjust = c(0, rep(1, ncol(table) - 1)),
                                      x = c(0.03, rep(0.97, ncol(table) - 1))))
    )
    grob <- gridExtra::tableGrob(table, rows = NULL, theme = theme)
    if (convertWidth(sum(grob$widths), "in", valueOnly = TRUE) <= max_width) break
  }
  grob
}

# Splits a table into blocks of at most `rows` rows (headers repeated)
split_table <- function(table, rows = 28) {
  starts <- seq(1, max(nrow(table), 1), by = rows)
  lapply(starts, function(s) table[s:min(s + rows - 1, nrow(table)), , drop = FALSE])
}

#' Width and height of a grob in inches
#'
#' grobWidth() / grobHeight() do not report the full size of gridExtra
#' tables (gtables), so their column widths and row heights are summed.
grob_size <- function(grob) {
  if (inherits(grob, "gtable")) {
    c(width = convertWidth(sum(grob$widths), "in", valueOnly = TRUE),
      height = convertHeight(sum(grob$heights), "in", valueOnly = TRUE))
  } else {
    c(width = convertWidth(grobWidth(grob), "in", valueOnly = TRUE),
      height = convertHeight(grobHeight(grob), "in", valueOnly = TRUE))
  }
}


#' Draw blocks (grobs) from top to bottom, starting new pages when needed
#'
#' @param blocks list of list(grob = <grob>, gap = <inches above the block>,
#'   keep_with_next = <TRUE for headings>).
#' @param footer text drawn at the bottom of every page (page number added).
draw_blocks <- function(blocks, footer) {
  page <- REPORT_PAGE
  top <- page$height - page$margin
  bottom <- page$margin + 0.3
  y <- top
  page_number <- 0

  new_page <- function() {
    # The first page is already open (see write_formulation_report())
    if (page_number > 0) grid.newpage()
    page_number <<- page_number + 1
    grid.text(pdf_text(sprintf("%s  |  page %d", footer, page_number)),
              x = unit(page$margin, "in"), y = unit(page$margin, "in"),
              hjust = 0, gp = gpar(fontsize = 7, col = "grey40"))
    y <<- top
  }
  height_of <- function(block) grob_size(block$grob)[["height"]]

  new_page()
  for (i in seq_along(blocks)) {
    block <- blocks[[i]]
    gap <- if (y == top) 0 else block$gap
    needed <- gap + height_of(block)
    # Keep headings on the same page as the block that follows them
    if (isTRUE(block$keep_with_next) && i < length(blocks)) {
      needed <- needed + blocks[[i + 1]]$gap + height_of(blocks[[i + 1]])
    }
    if (y - needed < bottom && y < top) {
      new_page()
      gap <- 0
    }
    y <- y - gap
    width <- grob_size(block$grob)[["width"]]
    pushViewport(viewport(x = unit(page$margin, "in"), y = unit(y, "in"),
                          width = unit(width, "in"), height = unit(height_of(block), "in"),
                          just = c("left", "top")))
    grid.draw(block$grob)
    popViewport()
    y <- y - height_of(block)
  }
  page_number
}

#' Write the PDF report
#'
#' @param file path of the PDF file to create.
#' @param report list created by new_formulation_report().
#' @return the number of pages, invisibly.
write_formulation_report <- function(file, report) {
  page <- REPORT_PAGE
  max_width <- page$width - 2 * page$margin

  pdf(file, width = page$width, height = page$height,
      title = "FeedR formulation report", paper = "a4")
  on.exit(dev.off())
  # Open the first page now: measuring the tables below needs an open page
  # (otherwise grid opens one implicitly and the PDF starts with a blank page)
  grid.newpage()

  heading <- function(text) {
    list(grob = text_grob(text, fontsize = 12, fontface = "bold"), gap = 0.35,
         keep_with_next = TRUE)
  }
  text <- function(lines, gap = 0.1, ...) list(grob = text_grob(lines, ...), gap = gap)
  tables <- function(table) {
    lapply(split_table(table), function(part) {
      list(grob = table_grob(part, max_width), gap = 0.12)
    })
  }

  result <- report$result
  blocks <- c(
    list(
      list(grob = text_grob("FeedR: Feed Formulation Report", fontsize = 18,
                            fontface = "bold"), gap = 0),
      text(sprintf("Created %s with FeedR v%s", format(report$created, "%Y-%m-%d %H:%M"),
                   FEEDR_VERSION), gap = 0.12, fontsize = 8),
      text(report_summary_lines(report), gap = 0.25)
    ),
    if (result$feasible) {
      c(list(heading("Calculated feed formulation")), tables(report_mix_table(report)))
    } else {
      list(heading("Why no solution was found"),
           text(result$diagnosis, gap = 0.1))
    },
    list(heading(if (result$feasible) "Nutrient composition" else "Nutrient targets")),
    tables(report_nutrient_table(report)),
    list(heading("Ingredient inputs")),
    tables(report_ingredient_table(report)),
    list(
      heading("Method"),
      text(c(
        paste("Inclusion rates are fractions of the mix that add up to 100 %. The",
              "nutrient content of the mix is the inclusion-weighted average of the",
              "ingredient contents. The formulation is solved as a linear program with",
              "the lpSolve package (see the FAQ tab of the app for the full model)."),
        paste("Targets with a maximum are treated as minimum-maximum ranges. In",
              "least-cost mode every target is a minimum. Inclusion limits restrict",
              "the share of individual ingredients."),
        "Cost share: cost contribution of each ingredient to 1 kg of the mix."
      ), fontsize = 8)
    )
  )

  pages <- draw_blocks(blocks, footer = sprintf("FeedR report  |  %s tab  |  %s",
                                                report$tab,
                                                format(report$created, "%Y-%m-%d %H:%M")))
  invisible(pages)
}
