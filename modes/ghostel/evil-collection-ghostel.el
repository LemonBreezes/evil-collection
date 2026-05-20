;;; evil-collection-ghostel.el --- Bindings for `ghostel' -*- lexical-binding: t -*-

;; Copyright (C) 2026 StrawberryTea

;; Author: StrawberryTea <luneth1314@gmail.com>
;; Maintainer: StrawberryTea <luneth1314@gmail.com>
;; URL: https://github.com/emacs-evil/evil-collection
;; Version: 0.0.1
;; Package-Requires: ((emacs "26.3"))
;; Keywords: evil, ghostel, ghostty, terminals, tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; Evil bindings for `ghostel', the libghostty-backed terminal emulator.
;;
;; Ghostel has several input modes — `semi-char' (the default; most keys
;; go to the terminal), `char' (every key goes to the terminal), `emacs'
;; (the buffer is read-only while the terminal stays live), `copy' (the
;; buffer is read-only and the terminal is paused), and `line' (the
;; in-progress input is editable as buffer text and sent on RET).
;;
;; Switching to Evil's insert state automatically switches to semi-char
;; mode; switching to normal state automatically switches to Emacs mode,
;; so vim-style navigation works over the scrollback while the terminal
;; keeps running.  Toggle this with
;; `evil-collection-ghostel-sync-state-and-mode-p'.

;;; Code:
(require 'evil-collection)
(require 'ghostel nil t)

(defconst evil-collection-ghostel-maps '(ghostel-mode-map
                                         ghostel-semi-char-mode-map
                                         ghostel-line-mode-map))

(declare-function ghostel-semi-char-mode "ghostel")
(declare-function ghostel-char-mode "ghostel")
(declare-function ghostel-emacs-mode "ghostel")
(declare-function ghostel-copy-mode "ghostel")
(declare-function ghostel-line-mode "ghostel")
(declare-function ghostel-send-key "ghostel")
(declare-function ghostel-send-string "ghostel")
(declare-function ghostel-send-C-c "ghostel")
(declare-function ghostel-send-C-z "ghostel")
(declare-function ghostel-send-C-d "ghostel")
(declare-function ghostel-send-C-g "ghostel")
(declare-function ghostel-send-C-backslash "ghostel")
(declare-function ghostel-yank "ghostel")
(declare-function ghostel-yank-pop "ghostel")
(declare-function ghostel-paste "ghostel")
(declare-function ghostel-clear-scrollback "ghostel")
(declare-function ghostel-next-prompt "ghostel")
(declare-function ghostel-previous-prompt "ghostel")
(declare-function ghostel-next-hyperlink "ghostel")
(declare-function ghostel-previous-hyperlink "ghostel")
(declare-function ghostel-open-link-at-point "ghostel")
(declare-function ghostel-copy-all "ghostel")
(declare-function ghostel-readonly-copy "ghostel")
(declare-function ghostel-beginning-of-input-or-line "ghostel")

(defvar ghostel--input-mode)
(defvar ghostel--process)

(defcustom evil-collection-ghostel-sync-state-and-mode-p t
  "Synchronize Evil's insert/normal state with ghostel's semi-char/emacs mode.

When non-nil, entering insert state switches the ghostel buffer to
`ghostel-semi-char-mode' so keystrokes flow to the terminal as usual,
and leaving insert state switches to `ghostel-emacs-mode' so the buffer
becomes read-only and Vim-style navigation works over the live
scrollback."
  :type 'boolean
  :group 'ghostel)

(defcustom evil-collection-ghostel-move-cursor-back nil
  "Whether the cursor moves backwards when exiting insert state.

Moving the cursor back one column is the default Vim behaviour, but in
a terminal it desynchronises Emacs's point from the terminal's live
cursor."
  :type 'boolean
  :group 'ghostel)

(defun evil-collection-ghostel-escape-stay ()
  "Do not move the cursor backwards when exiting insert state.
This keeps Emacs's point aligned with the terminal's cursor."
  (setq-local evil-move-cursor-back
              evil-collection-ghostel-move-cursor-back))

(defvar-local evil-collection-ghostel-send-escape-to-ghostel-p nil
  "Track whether ESC is sent to `ghostel' or handled by Emacs/Evil.")

(defun evil-collection-ghostel-toggle-send-escape ()
  "Toggle where ESC is sent between `ghostel' and `emacs'.

Useful for programs that rely on ESC (vim, an ssh'd Emacs running
`evil-mode', etc.).  When sending to ghostel, ESC in insert state
forwards a literal escape to the terminal instead of dropping back to
normal state."
  (interactive)
  (if evil-collection-ghostel-send-escape-to-ghostel-p
      (evil-collection-define-key 'insert 'ghostel-mode-map (kbd "<escape>")
        (lookup-key evil-insert-state-map (kbd "<escape>")))
    (evil-collection-define-key 'insert 'ghostel-mode-map
      (kbd "<escape>")
      'evil-collection-ghostel-send-escape))
  (setq evil-collection-ghostel-send-escape-to-ghostel-p
        (not evil-collection-ghostel-send-escape-to-ghostel-p))
  (message "Sending ESC to %s."
           (if evil-collection-ghostel-send-escape-to-ghostel-p
               "ghostel" "emacs")))

(defun evil-collection-ghostel-send-escape ()
  "Send a literal ESC keypress to the terminal."
  (interactive)
  (ghostel-send-key "escape"))

(defun evil-collection-ghostel-send-return ()
  "Send a Return keypress to the terminal.
Goes through ghostel's key encoder so the terminal's current mode
\(application cursor keys, kitty keyboard protocol, etc.) is honoured."
  (interactive)
  (ghostel-send-key "return"))

(defun evil-collection-ghostel-send-tab ()
  "Send a Tab keypress to the terminal."
  (interactive)
  (ghostel-send-key "tab"))

(defun evil-collection-ghostel-insert ()
  "Switch to insert state in the current ghostel buffer.
With `evil-collection-ghostel-sync-state-and-mode-p' non-nil this also
returns the buffer to `ghostel-semi-char-mode' via the insert-state
entry hook."
  (interactive)
  (evil-insert-state))

(defun evil-collection-ghostel-append ()
  "Switch to insert state at point.
Ghostel's renderer owns the cursor, so this does not move point — it
just hands control back to the terminal."
  (interactive)
  (evil-insert-state))

(defun evil-collection-ghostel-paste-after ()
  "Send a bracketed paste to the terminal.
Acts like Vim's `p' inside a terminal — the kill-ring text is forwarded
to the running program through bracketed paste (if enabled) so the
shell treats it as a single paste rather than typed input."
  (interactive)
  (ghostel-yank))

(defun evil-collection-ghostel-sync-on-insert-entry ()
  "Switch ghostel to semi-char mode on Evil insert-state entry."
  (when (and (derived-mode-p 'ghostel-mode)
             (boundp 'ghostel--input-mode)
             (not (eq ghostel--input-mode 'semi-char))
             (not (eq ghostel--input-mode 'char))
             (not (eq ghostel--input-mode 'line)))
    (ghostel-semi-char-mode)))

(defun evil-collection-ghostel-sync-on-insert-exit ()
  "Switch ghostel to Emacs mode when leaving Evil insert state.
A no-op when the buffer is in char or line mode — the user picked
those manually."
  (when (and (derived-mode-p 'ghostel-mode)
             (boundp 'ghostel--input-mode)
             (memq ghostel--input-mode '(semi-char)))
    (ghostel-emacs-mode)))

(defun evil-collection-ghostel-sync-state-and-mode ()
  "Wire up insert/normal-state hooks to ghostel's input modes."
  (add-hook 'evil-insert-state-entry-hook
            #'evil-collection-ghostel-sync-on-insert-entry nil t)
  (add-hook 'evil-insert-state-exit-hook
            #'evil-collection-ghostel-sync-on-insert-exit nil t))

;;;###autoload
(defun evil-collection-ghostel-setup ()
  "Set up `evil' bindings for `ghostel'."
  (evil-set-initial-state 'ghostel-mode 'insert)

  (add-hook 'ghostel-mode-hook #'evil-collection-ghostel-escape-stay)
  (if evil-collection-ghostel-sync-state-and-mode-p
      (add-hook 'ghostel-mode-hook
                #'evil-collection-ghostel-sync-state-and-mode)
    (remove-hook 'ghostel-mode-hook
                 #'evil-collection-ghostel-sync-state-and-mode))

  ;; Open to a better binding...
  (evil-collection-define-key '(normal insert) 'ghostel-mode-map
    (kbd "C-c C-z") 'evil-collection-ghostel-toggle-send-escape)

  ;; Evil shadows several "C-" keys in insert state that the shell
  ;; usually owns.  Forward them to the terminal so readline / zle /
  ;; tmux behave normally.  Don't raw-send "C-c" (prefix) or "C-h"
  ;; (help prefix) — those have ghostel-mode-map bindings.
  (let ((raw (lambda (key mods)
               (lambda ()
                 (interactive)
                 (ghostel-send-key key mods)))))
    (evil-collection-define-key 'insert 'ghostel-mode-map
      (kbd "C-a") (funcall raw "a" "ctrl")
      (kbd "C-b") (funcall raw "b" "ctrl")
      (kbd "C-d") (funcall raw "d" "ctrl")
      (kbd "C-e") (funcall raw "e" "ctrl")
      (kbd "C-f") (funcall raw "f" "ctrl")
      (kbd "C-k") (funcall raw "k" "ctrl")
      (kbd "C-l") (funcall raw "l" "ctrl")
      (kbd "C-n") (funcall raw "n" "ctrl")
      (kbd "C-o") (funcall raw "o" "ctrl")
      (kbd "C-p") (funcall raw "p" "ctrl")
      (kbd "C-q") (funcall raw "q" "ctrl")
      (kbd "C-r") (funcall raw "r" "ctrl")
      (kbd "C-s") (funcall raw "s" "ctrl")
      (kbd "C-t") (funcall raw "t" "ctrl")
      (kbd "C-u") (funcall raw "u" "ctrl")
      (kbd "C-v") (funcall raw "v" "ctrl")
      (kbd "C-w") (funcall raw "w" "ctrl")
      (kbd "C-y") (funcall raw "y" "ctrl")
      (kbd "C-z") (funcall raw "z" "ctrl")))

  ;; Submit-state RET (whichever state the user picked as their submit
  ;; state).  In line mode the map has its own RET, so this only fires
  ;; in semi-char / emacs / copy modes.
  (let ((submit evil-collection-repl-submit-state))
    (evil-collection-define-key submit 'ghostel-mode-map
      (kbd "RET") 'evil-collection-ghostel-send-return))

  (evil-collection-define-key 'normal 'ghostel-mode-map
    ;; Prompt navigation.
    "[[" 'ghostel-previous-prompt
    "]]" 'ghostel-next-prompt
    "gk" 'ghostel-previous-prompt
    "gj" 'ghostel-next-prompt
    ;; Hyperlink navigation (OSC 8, auto-detected URLs, file:line refs).
    "gh" 'ghostel-previous-hyperlink
    "gl" 'ghostel-next-hyperlink
    ;; Insert-like commands all just hand control back to the terminal;
    ;; ghostel's renderer owns the cursor so we don't try to reposition.
    "i" 'evil-collection-ghostel-insert
    "I" 'evil-collection-ghostel-insert
    "a" 'evil-collection-ghostel-append
    "A" 'evil-collection-ghostel-append
    "o" 'evil-collection-ghostel-append
    "O" 'evil-collection-ghostel-append
    ;; Paste forwards through bracketed paste to the running program.
    "p" 'evil-collection-ghostel-paste-after
    "P" 'ghostel-yank
    ;; Yank-pop only makes sense right after a paste.
    (kbd "M-y") 'ghostel-yank-pop
    ;; Convenience aliases for built-in commands.
    "gG" 'ghostel-copy-all
    ;; Beginning of input on a prompt row.
    "^" 'ghostel-beginning-of-input-or-line
    ;; Mode-switching shortcuts.
    "gC" 'ghostel-char-mode
    "gL" 'ghostel-line-mode
    "gE" 'ghostel-emacs-mode
    "gY" 'ghostel-copy-mode
    ;; Scrollback management.
    "ZZ" 'ghostel-clear-scrollback)

  (evil-collection-define-key 'visual 'ghostel-mode-map
    "y" 'ghostel-readonly-copy))

(provide 'evil-collection-ghostel)
;;; evil-collection-ghostel.el ends here
