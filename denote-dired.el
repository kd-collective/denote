;;; denote-dired.el --- Integration between Denote and Dired -*- lexical-binding: t -*-

;; Copyright (C) 2022  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; URL: https://git.sr.ht/~protesilaos/denote
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.2"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; One of the upsides of Denote's file-naming scheme is the predictable
;; pattern it establishes, which appears as a near-tabular presentation in
;; a listing of notes (i.e. in Dired).  The `denote-dired-mode' can help
;; enhance this impression, by fontifying the components of the file name
;; to make the date (identifier) and keywords stand out.
;;
;; There are two ways to set the mode.  Either use it for all directories,
;; which probably is not needed:
;;
;;     (require 'denote-dired)
;;     (add-hook 'dired-mode-hook #'denote-dired-mode)
;;
;; Or configure the user option `denote-dired-directories' and then set up
;; the function `denote-dired-mode-in-directories':
;;
;;     (require 'denote-dired)
;;
;;     ;; We use different ways to specify a path for demo purposes.
;;     (setq denote-dired-directories
;;           (list denote-directory
;;                 (thread-last denote-directory (expand-file-name "attachments"))
;;                 (expand-file-name "~/Documents/vlog")))
;;
;;     (add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)
;;
;; The `denote-dired-mode' does not only fontify note files that were
;; created by Denote: it covers every file name that follows our naming
;; conventions (read about "The file-naming scheme" in the manual).
;; This is particularly useful for scenaria where, say, one wants to
;; organise their collection of PDFs and multimedia in a systematic way
;; (and, perhaps, use them as attachments for the notes Denote
;; produces).
;;
;; For the time being, the `diredfl' package is not compatible with this
;; facility.

;;; Code:

(require 'denote-retrieve)
(require 'dired)

(defgroup denote-dired ()
  "Integration between Denote and Dired."
  :group 'denote)

(defcustom denote-dired-directories
  ;; We use different ways to specify a path for demo purposes.
  (list denote-directory
        (thread-last denote-directory (expand-file-name "attachments"))
        (expand-file-name "~/Documents/vlog"))
  "List of directories where `denote-dired-mode' should apply to."
  :type '(repeat directory)
  :group 'denote-dired)

(defcustom denote-dired-rename-expert nil
  "If t, `denote-dired-rename-file' doesn't ask for confirmation.
The confiration is asked via a `y-or-n-p' prompt which shows the
old name followed by the new one."
  :type 'boolean
  :group 'denote-dired)

(defcustom denote-dired-post-rename-functions
  (list #'denote-dired-rewrite-front-matter)
  "List of functions called after `denote-dired-rename-file'.
Each function must accept three arguments: FILE, TITLE, and
KEYWORDS.  The first is the full path to the file provided as a
string, the second is the human-readable file name (not what
Denote sluggifies) also as a string, and the third are the
keywords.  If there is only one keyword, it is a string, else a
list of strings.

DEVELOPMENT NOTE: the `denote-dired-rewrite-front-matter' needs
to be tested thoroughly.  It rewrites file contents so we have to
be sure it does the right thing.  To avoid any trouble, it always
asks for confirmation before performing the replacement.  This
confirmation ignores `denote-dired-rename-expert' for the time
being, though we might want to lift that restriction once
everything works as intended."
  :type 'hook
  :group 'denote-dired)

;;;; Commands

(defun denote-dired--file-attributes-time (file)
  "Return `file-attribute-modification-time' of FILE as identifier."
  (format-time-string
   denote--id-format
   (file-attribute-modification-time (file-attributes file))))

(defun denote-dired--file-name-id (file)
  "Return FILE identifier, else generate one."
  (cond
   ((string-match denote--id-regexp file)
    (substring file (match-beginning 0) (match-end 0)))
   ((denote-dired--file-attributes-time file))
   (t (format-time-string denote--id-format))))

;;;###autoload
(defun denote-dired-rename-file (file title keywords)
  "Rename FILE to include TITLE and KEYWORDS.

If in Dired, consider FILE to be the one at point, else prompt
with completion.

If FILE has a Denote-compliant identifier, retain it while
updating the TITLE and KEYWORDS fields of the file name.  Else
create an identifier based on the file's attribute of last
modification time.  If such attribute cannot be found, the
identifier falls back to the current time.

As a final step, prompt for confirmation, showing the difference
between old and new file names.  If `denote-dired-rename-expert'
is non-nil, conduct the renaming operation outright---no
questions asked!

The file type extension (e.g. .pdf) is read from the underlying
file and is preserved through the renaming process.  Files that
have no extension are simply left without one.

Renaming only occurs relative to the current directory.  Files
are not moved between directories.  As a final step, call the
`denote-dired-post-rename-functions'.

This command is intended to (i) rename existing Denote
notes, (ii) complement note-taking, such as by renaming
attachments that the user adds to their notes."
  (interactive
   (list
    (or (dired-get-filename nil t) (read-file-name "Rename file Denote-style: "))
    (denote--title-prompt)
    (denote--keywords-prompt)))
  (let* ((dir (file-name-directory file))
         (old-name (file-name-nondirectory file))
         (extension (file-name-extension file t))
         (new-name (denote--format-file
                    dir
                    (denote-dired--file-name-id file)
                    keywords
                    (denote--sluggify title)
                    extension)))
    (unless (string= old-name (file-name-nondirectory new-name))
      (when (y-or-n-p
             (format "Rename %s to %s?"
                     (propertize old-name 'face 'error)
                     (propertize (file-name-nondirectory new-name) 'face 'success)))
        (rename-file old-name new-name nil)
        (when (derived-mode-p 'dired-mode)
          (revert-buffer))
        (run-hook-with-args 'denote-dired-post-rename-functions new-name title keywords)))))

(defun denote-dired--file-meta-header (title date keywords id filetype)
  "Front matter for renamed notes.

TITLE, DATE, KEYWORDS, FILENAME, ID, and FILETYPE are all strings
 which are provided by `denote-dired-rewrite-front-matter'."
  (let ((kw-space (denote--file-meta-keywords keywords))
        (kw-toml (denote--file-meta-keywords keywords 'toml)))
    (pcase filetype
      ('markdown-toml (format denote-toml-front-matter title date kw-toml id))
      ('markdown-yaml (format denote-yaml-front-matter title date kw-space id))
      ('text (format denote-text-front-matter title date kw-space id denote-text-front-matter-delimiter))
      (_ (format denote-org-front-matter title date kw-space id)))))

(defun denote-dired--filetype-heuristics (file)
  "Return likely file type of FILE.
The return value is for `denote--file-meta-header'."
  (pcase (file-name-extension file)
    ("md" (if (string-match-p "title\\s-*=" (denote-retrieve--value-title file 0))
              'markdown-toml
            'markdown-yaml))
    ("txt" 'text)
    (_ 'org)))

(defun denote-dired--front-matter-search-delimiter (filetype)
  "Return likely front matter delimiter search for FILETYPE."
  (pcase filetype
    ('markdown-toml (re-search-forward "^\\+\\+\\+$" nil t 2))
    ('markdown-yaml (re-search-forward "^---$" nil t 2))
    ;; 2 at most, as the user might prepend it to the block as well.
    ;; Though this might give us false positives, it ultimately is the
    ;; user's fault.
    ('text (or (re-search-forward denote-text-front-matter-delimiter nil t 2)
               (re-search-forward denote-text-front-matter-delimiter nil t 1)
               (re-search-forward "^[\s\t]*$" nil t 1)))
    ;; Org does not have a real delimiter.  This is the trickiest one.
    (_ (re-search-forward "^[\s\t]*$" nil t 1))))

(defun denote-dired--edit-front-matter-p (file)
  "Test if FILE should be subject to front matter rewrite."
  (when-let ((ext (file-name-extension file)))
    (and (file-regular-p file)
         (file-writable-p file)
         (not (denote--file-empty-p file))
         (string-match-p "\\(md\\|org\\|txt\\)\\'" ext)
         ;; Heuristic to check if this is one of our notes
         (string= default-directory (abbreviate-file-name (denote-directory))))))

(defun denote-dired-rewrite-front-matter (file title keywords)
  "Rewrite front matter of note after `denote-dired-rename-file'.
The FILE, TITLE, and KEYWORDS are passed from the renaming
 command and are used to construct a new front matter block."
  (when (denote-dired--edit-front-matter-p file)
    (when-let* ((id (denote-retrieve--filename-identifier file))
                (date (denote-retrieve--value-date file))
                (filetype (denote-dired--filetype-heuristics file))
                (new-front-matter (denote--file-meta-header title date keywords id filetype)))
      (let (old-front-matter front-matter-delimiter)
        (with-current-buffer (find-file-noselect file)
          (save-excursion
            (save-restriction
              (widen)
              (goto-char (point-min))
              (setq front-matter-delimiter (denote-dired--front-matter-search-delimiter filetype))
              (when front-matter-delimiter
                (setq old-front-matter
                      (buffer-substring-no-properties
                       (point-min)
                       (progn front-matter-delimiter (point)))))))
          (when (and old-front-matter
                     (y-or-n-p
                      (format "%s\n%s\nReplace front matter?"
                              (propertize old-front-matter 'face 'error)
                              (propertize new-front-matter 'face 'success))))
            (delete-region (point-min) front-matter-delimiter)
            (goto-char (point-min))
            (insert new-front-matter)
            ;; FIXME 2022-06-16: Instead of `delete-blank-lines', we
            ;; should check if we added any new lines and delete only
            ;; those.
            (delete-blank-lines)))))))

;;;; Extra fontification

(defface denote-dired-field-date
  '((((class color) (min-colors 88) (background light))
     :foreground "#00538b")
    (((class color) (min-colors 88) (background dark))
     :foreground "#00d3d0")
    (t :inherit font-lock-variable-name-face))
  "Face for file name date in `dired-mode' buffers."
  :group 'denote-dired)

(defface denote-dired-field-time
  '((t :inherit denote-dired-field-date))
  "Face for file name time in `dired-mode' buffers."
  :group 'denote-dired)

(defface denote-dired-field-title
  '((t ))
  "Face for file name title in `dired-mode' buffers."
  :group 'denote-dired)

(defface denote-dired-field-extension
  '((t :inherit shadow))
  "Face for file extension type in `dired-mode' buffers."
  :group 'denote-dired)

(defface denote-dired-field-keywords
  '((default :inherit bold)
    (((class color) (min-colors 88) (background light))
     :foreground "#8f0075")
    (((class color) (min-colors 88) (background dark))
     :foreground "#f78fe7")
    (t :inherit font-lock-builtin-face))
  "Face for file name keywords in `dired-mode' buffers."
  :group 'denote-dired)

(defface denote-dired-field-delimiter
  '((((class color) (min-colors 88) (background light))
     :foreground "gray70")
    (((class color) (min-colors 88) (background dark))
     :foreground "gray30")
    (t :inherit shadow))
  "Face for file name delimiters in `dired-mode' buffers."
  :group 'denote-dired)

(defconst denote-dired-font-lock-keywords
  `((,denote--file-regexp
     (1 'denote-dired-field-date)
     (2 'denote-dired-field-time)
     (3 'denote-dired-field-delimiter)
     (4 'denote-dired-field-title)
     (5 'denote-dired-field-delimiter)
     (6 'denote-dired-field-keywords)
     (7 'denote-dired-field-extension))
    ("_"
     (0 'denote-dired-field-delimiter t)))
  "Keywords for fontification.")

;;;###autoload
(define-minor-mode denote-dired-mode
  "Fontify all Denote-style file names in Dired."
  :global nil
  :group 'denote-dired
  (if denote-dired-mode
      (font-lock-add-keywords nil denote-dired-font-lock-keywords t)
    (font-lock-remove-keywords nil denote-dired-font-lock-keywords))
  (font-lock-flush (point-min) (point-max)))

(defun denote-dired--modes-dirs-as-dirs ()
  "Return `denote-dired-directories' as directories.
The intent is to basically make sure that however a path is
written, it is always returned as a directory."
  (mapcar
   (lambda (dir)
     (file-name-as-directory (file-truename dir)))
   denote-dired-directories))

;;;###autoload
(defun denote-dired-mode-in-directories ()
  "Enable `denote-dired-mode' in `denote-dired-directories'.
Add this function to `dired-mode-hook'."
  (when (member (file-truename default-directory) (denote-dired--modes-dirs-as-dirs))
    (denote-dired-mode 1)))

(provide 'denote-dired)
;;; denote-dired.el ends here
