###########################################################################/**
# @RdocClass RspParser
#
# @title "The RspParser class"
#
# \description{
#  @classhierarchy
#
#  An RspParser is parser for the RSP language.
# }
# 
# @synopsis
#
# \arguments{
#   \item{...}{Not used.}
# }
#
# \section{Fields and Methods}{
#  @allmethods
# }
# 
# @author
#
# @keyword internal
#*/###########################################################################
setConstructorS3("RspParser", function(...) {
  extend(NA, "RspParser");
})


#########################################################################/**
# @RdocMethod parseRaw
#
# @title "Parses the string into blocks of text and RSP"
#
# \description{
#  @get "title".
# }
#
# @synopsis
#
# \arguments{
#   \item{object}{An @see RspString to be parsed.}
#   \item{what}{A @character string specifying what type of RSP construct
#     to parse for.}
#   \item{commentLength}{Specify the number of hypens in RSP comments
#     to parse for.}
#   \item{...}{Not used.}
#   \item{verbose}{See @see "R.utils::Verbose".}
# }
#
# \value{
#  Returns a named @list with elements named "text" and "rsp".
# }
#
# @author
#
# \seealso{
#   @seeclass
# }
#*/######################################################################### 
setMethodS3("parseRaw", "RspParser", function(parser, object, what=c("comment", "directive", "expression"), commentLength=-1L, ..., verbose=FALSE) {
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Local functions
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  countLineBreaks <- function(s, ...) {
    s <- gsub("\r\n", "\n", s, fixed=TRUE);
    s <- gsub("\r", "\n", s, fixed=TRUE);
    s <- charToRaw(s);
    sum(s == as.raw(0x0a));
  } # countLineBreaks()


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Validate arguments
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Argument 'what':
  what <- match.arg(what);

  # Argument 'commentLength':
  commentLength <- as.integer(commentLength);
  stopifnot(is.finite(commentLength));
  stopifnot(commentLength == -1L || commentLength >= 2L);

  # Argument 'verbose':
  verbose <- Arguments$getVerbose(verbose);
  if (verbose) {
    pushState(verbose);
    on.exit(popState(verbose));
  }


  verbose && enter(verbose, "Raw parsing of RSP string");

  # Work with one large character string
  bfr <- paste(object, collapse="\n", sep="");
  verbose && cat(verbose, "Length of RSP string: ", nchar(bfr));


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Setup
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Pattern for suffix specification
##  patternS <- "(([+]))|([-]+\\[([^]]*)\\])?%>";
  patternS <- "([+]|[-]+(\\[[^]]*\\])?)%>";

  # Setup the regular expressions for start and stop RSP constructs
  if (what == "comment") {
    if (commentLength == -1L) {
      patternL <- "<%([-]+(\\[[^]]*\\])?%>)()";
      patternR <- NULL;
    } else {
      patternL <- sprintf("<%%-{%d}()([^-])", commentLength);
      patternR <- sprintf("(|[^-])(-{%d}(\\[[^]]*\\])?)%%>", commentLength);
    }
    bodyClass <- RspComment;
  } else if (what == "directive") {
    patternL <- "<%@()()";
    patternR <- "()(|[+]|-(\\[[^]]*\\])?)%>";
    bodyClass <- RspUnparsedDirective;
  } else if (what == "expression") {
    patternL <- "<%()()";
    patternR <- "()(|[+]|-(\\[[^]]*\\])?)%>";
    bodyClass <- RspUnparsedExpression;
  }

  if (verbose) {
    cat(verbose, "Regular expression patterns to use:");
    str(verbose, list(patternL=patternL, patternR=patternR, patternS=patternS));
    cat(verbose, "Class to coerce to: ", class(bodyClass())[1L]);
  }

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Parse
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  verbose && cat(verbose, "What to parse for: ", what);

  # Record source line
  lineCount <- 0L;

  # Specifies whether the RSP construct being parsed is on the same
  # line as an RSP text construct.
##  sameLineAsRspText <- FALSE;

  # Constants
  START <- 0L;
  STOP <- 1L;

  parts <- list();
  state <- START;
  while(TRUE) {
    if (state == START) {
      # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      # (a) Scan for RSP start tag, i.e. <%, <%@, or <%--
      # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      # The start tag may exists *anywhere* in static code
      posL <- regexpr(patternL, bfr);
      if (posL == -1L)
        break;
      nL <- attr(posL, "match.length");
      stopifnot(is.integer(nL));

      # (i) Extract RSP construct, '<%...%>[extra]'
      tag <- substring(bfr, first=posL, posL+nL-1L);

      # Was it an escaped RSP start tag, i.e. '<%%'?
      if (what == "expression") {
        tagX <- substring(bfr, first=posL, posL+nL);
        if (tagX == "<%%")
          break;
      }

      # If parsed too far, i.e. into the tailing text
      # (so that '[extra]' is non-empty), then adjust
      bfrExtra <- gsub(patternL, "\\4", tag);
      nExtra <- nchar(bfrExtra);
      nL <- nL - nExtra;
      rm(bfrExtra);


      # (ii) Extract the preceeding text
      text <- substring(bfr, first=1L, last=posL-1L);
     
      # Record RSP text, unless empty.
      if (nchar(text) > 0L) {
        # Update flag whether the RSP construct being parsed is
        # on the same output line as RSP text or not.  It is not
        # if the text ends with a line break.
##        sameLineAsRspText <- (regexpr("[\n\r]$", text) == -1L);
        part <- list(text=RspText(text));
      } else {
##        sameLineAsRspText <- FALSE;
        part <- NULL;
      }


      # (iii) Special case: Locate RSP end tag immediately.
      if (is.null(patternR)) {
        body <- "";

##        # Record 'same-line-as-text' flag
##        attr(body, "sameLineAsRspText") <- sameLineAsRspText;

        # Extract the '<%...%>' part
        if (nExtra > 0L) {
          tail <- substring(tag, first=1L, last=nL-1L);
        } else {
          tail <- tag;
        }
        # Extract the '...%>' part
        tail <- gsub(patternL, "\\1", tail);

        # Get optional suffix specifications, i.e. '+%>' or '-[{specs}]%>'
        if (regexpr(patternS, tail) != -1L) {
          suffixSpecs <- gsub(patternS, "\\1", tail);
          suffixSpecs <- gsub("--*", "-", suffixSpecs);
          verbose && printf(verbose, "Identified suffix specification: '%s'\n", suffixSpecs);
          attr(body, "suffixSpecs") <- suffixSpecs;
        } else {
          verbose && cat(verbose, "Identified suffix specification: <none>");
        }

        if (what == "comment") {
          attr(body, "commentLength") <- commentLength;           
        }

        if (!is.null(bodyClass)) {
          body <- bodyClass(body);
        }

        part2 <- list(rsp=body);
        if (what != "expression") {
          names(part2)[1L] <- what;
        }
        part <- c(part, part2);
        state <- START;
      } else {
        state <- STOP;
      }

      # (iv) Finally, consume the read buffer
      bfr <- substring(bfr, first=posL+nL);
    } else if (state == STOP) {
      # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      # (b) Scan for RSP end tag, i.e. %>, %>, or --%>
      # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      # Not found?
      posR <- indexOfNonQuoted(bfr, patternR);
      if (posR == -1L)
        break;

      # (i) Extract RSP body with RSP end tag, '[extra][pattern]%>'
      nR <- attr(posR, "match.length");
      tail <- substring(bfr, first=posR, last=posR+nR-1L);

      # Was it an escaped RSP end tag, i.e. '%%>'?
      if (what == "expression") {
        nT <- nchar(tail);
        if (nT >= 3L && substring(tail, first=nT-2L, last=nT) == "%%>")
          break;
      }

      # If parsed too far, i.e. into the preceeding body
      # (so that '[extra]' is non-empty), then adjust
      bodyExtra <- gsub(patternR, "\\1", tail);
      nExtra <- nchar(bodyExtra);
      posR <- posR + nExtra;
      nR <- nR - nExtra;
      rm(bodyExtra);

      # Extract body of RSP construct (without RSP end tag)
      body <- substring(bfr, first=1L, last=posR-1L);

##      # Record 'same-line-as-text' flag
##      attr(body, "sameLineAsRspText") <- sameLineAsRspText;

      # Get optional suffix specifications, i.e. '+%>' or '-[{specs}]%>'
      if (regexpr(patternS, tail) == 1L) {
        suffixSpecs <- gsub(patternS, "\\1", tail);
        verbose && printf(verbose, "Identified suffix specification: '%s'\n", suffixSpecs);
        attr(body, "suffixSpecs") <- suffixSpecs;
      } else {
        verbose && cat(verbose, "Identified suffix specification: <none>");
      }

      if (what == "comment") {
        attr(body, "commentLength") <- commentLength;           
      }

      if (!is.null(bodyClass)) {
        body <- bodyClass(body);
      }

      part <- list(rsp=body);
      if (what != "expression") {
        names(part)[1L] <- what;
      }

      # (iv) Finally, consume the read buffer
      bfr <- substring(bfr, first=posR+nR);

      state <- START;
    } # if (state == ...)

    parts <- c(parts, part);

    verbose && cat(verbose, "RSP construct(s) parsed:");
    verbose && print(verbose, part);
    verbose && cat(verbose, "Number of RSP constructs parsed this far: ", length(parts));
  } # while(TRUE);

  # Add the rest of the buffer as text, unless empty.
  if (nchar(bfr) > 0L) {
    text <- RspText(bfr);
    parts <- c(parts, list(text=text));
  }
  verbose && cat(verbose, "Total number of RSP constructs parsed: ", length(parts));

  # Setup results
  doc <- RspDocument(parts, type=getType(object), source=getSource(object), annotations=getAnnotations(object));
  attr(doc, "what") <- what;

  verbose && exit(verbose);

  doc;
}, protected=TRUE) # parseRaw()



#########################################################################/**
# @RdocMethod parse
#
# @title "Parses the RSP string"
#
# \description{
#  @get "title" with RSP comments dropped.
# }
#
# @synopsis
#
# \arguments{
#   \item{object}{An @see RspString to be parsed.}
#   \item{envir}{The @environment where the RSP document is preprocessed.}
#   \item{...}{Passed to the processor in each step.}
#   \item{until}{Specifies how far the parse should proceed, which is useful
#      for troubleshooting and rebugging.}
#   \item{as}{Specifies in what format the parsed RSP document
#      should be returned.}
#   \item{verbose}{See @see "R.utils::Verbose".}
# }
#
# \value{
#  Returns a @see "RspDocument" (when \code{as = "RspDocument"}; default)
#  or @see "RspString" (when \code{as = "RspString"}).
# }
#
# @author
#
# \seealso{
#   @seeclass
# }
#*/######################################################################### 
setMethodS3("parse", "RspParser", function(parser, object, envir=parent.frame(), ..., until=c("*", "end", "expressions", "directives", "comments"), as=c("RspDocument", "RspString"), verbose=FALSE) {
  # Load the package (super quietly), in case R.rsp::nnn() was called.
  suppressPackageStartupMessages(require("R.rsp", quietly=TRUE)) || throw("Package not loaded: R.rsp");

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Validate arguments
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Argument 'until':
  until <- match.arg(until);

  # Argument 'as':
  as <- match.arg(as);

  # Argument 'verbose':
  verbose <- Arguments$getVerbose(verbose);
  if (verbose) {
    pushState(verbose);
    on.exit(popState(verbose));
  }


  verbose && enter(verbose, "Parsing RSP string");
  verbose && cat(verbose, "Compile until: ", sQuote(until));
  verbose && cat(verbose, "Return as: ", sQuote(as));

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # (1a) Parse and drop "empty" RSP comments
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  verbose && enter(verbose, "Dropping 'empty' RSP comments");
  verbose && cat(verbose, "Length of RSP string before: ", nchar(object));

  doc <- parseRaw(parser, object, what="comment", commentLength=-1L, verbose=less(verbose, 50));

  idxs <- which(sapply(doc, FUN=inherits, "RspComment"));
  count <- length(idxs);

  # Empty comments found?
  if (count > 0L) {
    verbose && print(verbose, doc);

    # Preprocess, drop RspComments and adjust for empty lines
    doc <- preprocess(doc, verbose=less(verbose, 10));
    verbose && print(verbose, doc);

    verbose && cat(verbose, "Number of 'empty' RSP comments dropped: ", count);

    # Coerce to RspString
    object <- asRspString(doc);
    verbose && cat(verbose, "Length of RSP string after: ", nchar(object));
  } else {
    verbose && cat(verbose, "No 'empty' RSP comments found.");
  }

  verbose && exit(verbose);

  if (until == "comments") {
    verbose && exit(verbose);
    if (as == "RspDocument") {
      return(doc);
    } else if (as == "RspString") {
      return(object);
    }
  }


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # (1b) Parse and drop RSP comments
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  verbose && enter(verbose, "Dropping 'paired' RSP comments");
  verbose && cat(verbose, "Length of RSP string before: ", nchar(object));

  count <- 0L;
  posL <- -1L;
  while ((pos <- regexpr("<%[-]+", object)) != -1L) {
    # Nothing changed? (e.g. if there is an unclosed comment)
    if (identical(pos, posL)) {
      break;
    }

    # Identify the comment length of the first comment found
    n <- attr(pos, "match.length") - 2L;
    stopifnot(n >= 2L);

    verbose && printf(verbose, "Number of hypens of first comment found: %d\n", n);

    # Find all comments of this same length
    doc <- parseRaw(parser, object, what="comment", commentLength=n, verbose=less(verbose, 50));

    idxs <- which(sapply(doc, FUN=inherits, "RspComment"));
    count <- count + length(idxs);

    # Trim non-text RSP constructs
    doc <- trimNonText(doc, verbose=less(verbose, 10));

    # Preprocess (=drop RspComments and adjust for empty lines)
    doc <- preprocess(doc, verbose=less(verbose, 10));

    # Coerce to RspString
    object <- asRspString(doc);

    posL <- pos;
##    rm(doc);
  }

  if (count > 0L) {
    verbose && cat(verbose, "Number of 'paired' RSP comments dropped: ", count);
    verbose && cat(verbose, "Length of RSP string after: ", nchar(object));
  } else {
    verbose && cat(verbose, "No 'paired' RSP comments found.");
  }

  verbose && exit(verbose);


  if (until == "directives") {
    verbose && exit(verbose);
    if (as == "RspDocument") {
      docP <- parseRaw(parser, object, what="directive", verbose=less(verbose, 50));
      return(docP);
    } else if (as == "RspString") {
      return(object);
    }
  }


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # (2a) Parse RSP preprocessing directive
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  verbose && enter(verbose, "Processing RSP preprocessing directives");
  verbose && cat(verbose, "Length of RSP string before: ", nchar(object));

  doc <- parseRaw(parser, object, what="directive", verbose=less(verbose, 50));
  idxs <- which(sapply(doc, FUN=inherits, "RspUnparsedDirective"));
  if (length(idxs) > 0L) {
    verbose && cat(verbose, "Number of (unparsed) RSP preprocessing directives found: ", length(idxs));

    # Parse each of them
    for (idx in idxs) {
      doc[[idx]] <- parse(doc[[idx]]);
    }

    # Trim non-text RSP constructs
    doc <- trimNonText(doc, verbose=less(verbose, 10));

    # Process all RSP preprocessing directives, i.e. <%@...%>
    doc <- preprocess(doc, envir=envir, ..., verbose=less(verbose, 10));

    # Coerce to RspString
    object <- asRspString(doc);
    verbose && cat(verbose, "Length of RSP string after: ", nchar(object));
  } else {
    verbose && cat(verbose, "No RSP preprocessing directives found.");
  }
  rm(idxs);
##  rm(doc, idxs);

  verbose && exit(verbose);

  if (until == "expressions") {
    verbose && exit(verbose);
    if (as == "RspDocument") {
      return(doc);
    } else if (as == "RspString") {
      return(object);
    }
  }


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # (3) Parse RSP expressions
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  verbose && enter(verbose, "Processing RSP expressions");
  verbose && cat(verbose, "Length of RSP string before: ", nchar(object));

  doc <- parseRaw(parser, object, what="expression", verbose=less(verbose, 50));
  idxs <- which(sapply(doc, FUN=inherits, "RspUnparsedExpression"));

  if (length(idxs) > 0L) {
    verbose && cat(verbose, "Number of (unparsed) RSP expressions found: ", length(idxs));

    # Parse them
    for (idx in idxs) {
      doc[[idx]] <- parse(doc[[idx]]);
    }

    # Trim non-text RSP constructs
    doc <- trimNonText(doc, verbose=less(verbose, 10));

    # Preprocess (=trim all empty lines)
    doc <- preprocess(doc, envir=envir, ..., verbose=less(verbose, 10));

    if (verbose && isVisible(verbose)) {
      object <- asRspString(doc);
      verbose && cat(verbose, "Length of RSP string after: ", nchar(object));
    }
  } else {
    verbose && cat(verbose, "No RSP expressions found.");
  }

  verbose && exit(verbose);

  if (until == "end") {
    verbose && exit(verbose);
    if (as == "RspDocument") {
      return(doc);
    } else if (as == "RspString") {
      return(object);
    }
  }

  verbose && exit(verbose);

  if (as == "RspDocument") {
    return(doc);
  } else if (as == "RspString") {
    object <- asRspString(doc);
    return(object);
  }
}, protected=TRUE) # parse()



##############################################################################
# HISTORY:
# 2013-03-10
# o FIX: Now parse() trims non-text RSP constructs both before and after
#   parsing each of them.  This fixed the problem of extraneous line breaks
#   when consecutive RSP constructs exists.
# 2013-03-09
# o Created by extracting the code of RspString that does parsing.
#   Comments below reflect such code.
# 2013-03-08
# o Now parseRaw() handles RSP tags '<%%' and '%%>'.
# 2013-02-23
# o Now parseRaw() always ignores empty text, i.e. it never adds an
#   empty RspText object.
# o Readded trim() at the end of parse().
# o Added verbose output to parse().
# o Replaced argument 'preprocess' with 'until' for parse().
# 2013-02-22
# o Major update of parse() for RspString to the state where RSP comments
#   can contain anything, RSP preprocessing directives can be located 
#   anywhere including inside RSP expressions (but not inside RSP comments).
#   This means that it is possible to for instance dynamically include code
#   into an RSP code expression using and <%@include ...%> directive.
# 2013-02-19
# o RSP comments must be dropped by the RSP parser at the very beginning,
#   otherwise they cannot be nested.  All other RSP constructs must not
#   be nested.
# o Added support for RSP comments of format <%-+[{count}]%>', where {count}
#   specifies the maximum number of empty lines to drop after the comment,
#   including the trailing whitespace and newline of the current line.
#   If {count} is negative, it drops all but the last {count} empty rows.
#   If {count} is zero, nothing is dropped.
# 2013-02-18
# o BUG FIX: Preprocessing directives without attributes where not recognized.
# 2013-02-12
# o Added support for nested RSP comments, by introducing "different" RSP
#   comment styles: <%-- --%>, <%--- ---%>, <%---- ----%>, and so on.
# 2013-02-11
# o Added Rdoc help.
# 2013-02-09
# o Created.
##############################################################################