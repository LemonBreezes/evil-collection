;;; evil-collection-corfu.el --- Bindings for `corfu-mode' -*- lexical-binding: t -*-

;; Copyright (C) 2022 James Nguyen

;; Author: James Nguyen <james@jojojames.com>
;; Maintainer: James Nguyen <james@jojojames.com>
;; URL: https://github.com/emacs-evil/evil-collection
;; Version: 0.0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: evil, corfu, convenience, matching

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
;;; Bindings for `corfu-mode'.

;;; Code:
(require 'corfu nil t)
(require 'evil-collection)

(defgroup evil-collection-corfu nil
  "Evil bindings for `corfu-mode'."
  :group 'evil-collection)

(defvar corfu-map)
(defvar corfu-cycle)
(defvar corfu-preselect)
(defvar corfu--index)

(declare-function corfu-insert "corfu")
(declare-function corfu-reset "corfu")
(declare-function corfu-quit "corfu")

(defconst evil-collection-corfu-maps '(corfu-map))

(defun evil-collection-corfu-quit-and-escape ()
  "Call `corfu-quit' and then return to Normal State."
  (interactive)
  (call-interactively 'corfu-quit)
  (evil-normal-state))

;; https://github.com/minad/corfu/pull/169
;; https://github.com/minad/corfu/pull/225
(defun evil-collection-corfu-unread-this-command-keys ()
  (when (> (length (this-command-keys)) 0)
    (setq unread-command-events (nconc
                                  (listify-key-sequence (this-command-keys))
                                  unread-command-events))
    (clear-this-command-keys t)))

(defun evil-collection-corfu-insert-exact ()
  "Insert current candidate with the `exact' status.
Quit if no candidate is selected."
  (interactive)
  (if (>= corfu--index 0)
      (corfu--insert 'exact)
    (corfu-quit)))

(defcustom evil-collection-corfu-key-themes '(default)
  "Determines the key theme to be mapped.

This variable should be set before `evil-collection-corfu-setup' is called.

By default, only default is added to this list as the other key themes might
be too obtrusive.

This key theme variable may be refactored in the future so use with caution."
  :type
  '(repeat
    :tag "Key Themes"
    (choice
     (const
      :tag "Default Theme" default)
     (const
      :tag "Tab & Go" tab-n-go)
     (const
      :tag "Magic Return" magic-return)
     (const
      :tag "Magic Backspace" magic-backspace))))

(defcustom evil-collection-corfu-supported-states '(insert replace emacs)
  "The `evil-state's which `corfu' function can be requested."
  :type '(repeat symbol))

;;;###autoload
(defun evil-collection-corfu-setup ()
  "Set up `evil' bindings for `corfu'."
  (when (memq 'default evil-collection-corfu-key-themes)
    (evil-collection-define-key 'insert 'corfu-map
      (kbd "C-n") 'corfu-next
      (kbd "C-p") 'corfu-previous
      (kbd "C-j") 'corfu-next
      (kbd "C-k") 'corfu-previous
      (kbd "M-j") 'corfu-next
      (kbd "M-k") 'corfu-previous
      (kbd "<down>") 'corfu-next
      (kbd "<up>") 'corfu-previous
      (kbd "<escape>") 'evil-collection-corfu-quit-and-escape))

  ;; https://github.com/minad/corfu#tab-and-go-completion
  (when (memq 'tab-n-go evil-collection-corfu-key-themes)
    (setq corfu-cycle t
          corfu-preselect 'prompt)
    (evil-collection-define-key 'insert 'corfu-map
      (kbd "TAB") 'corfu-next
      [tab] 'corfu-next
      [S-tab] 'corfu-previous
      [backtab] 'corfu-previous))

  (when (memq 'magic-return evil-collection-corfu-key-themes)
    (defvar evil-collection-corfu-insert-or-next-line
      `(menu-item "" nil :filter ,(lambda (&optional _)
                                    (when (>= corfu--index 0)
                                      'corfu-insert)))
      "If we made a selection during `corfu' completion, select it.")
    ;; FIXME: Not sure why we need to use `define-key' here instead of
    ;; `evil-collection-define-key';.
    (when (evil-collection-can-bind-key "RET")
      (define-key corfu-map (kbd "RET")
        evil-collection-corfu-insert-or-next-line)))

  (when (memq 'magic-backspace evil-collection-corfu-key-themes)
    (defvar evil-collection-corfu-cancel-or-backspace
      `(menu-item "" nil :filter ,(lambda (&optional _)
                                    (when (>= corfu--index 0)
                                      'corfu-reset)))
      "If we made a selection during `corfu' completion, cancel it.")
    (evil-collection-define-key 'insert
      'corfu-map (kbd "DEL") evil-collection-corfu-cancel-or-backspace)
    (evil-collection-define-key 'insert
      'corfu-map [backspace] evil-collection-corfu-cancel-or-backspace)
    (evil-collection-define-key 'insert
      'corfu-map (kbd "<backspace>") evil-collection-corfu-cancel-or-backspace))

  (when evil-want-C-u-scroll
    (evil-collection-define-key 'insert 'corfu-map
      (kbd "C-d") 'corfu-scroll-up))
  (when evil-want-C-d-scroll
    (evil-collection-define-key 'insert 'corfu-map
      (kbd "C-u") 'corfu-scroll-down))

  (advice-add 'corfu--setup :after (lambda (&rest _) (evil-normalize-keymaps)))
  (advice-add 'corfu--teardown :after (lambda (&rest _) (evil-normalize-keymaps)))
  (advice-add 'corfu--continue-p
              :before-while (lambda (&rest _) (memq evil-state evil-collection-corfu-supported-states)))

  (cl-defmethod corfu--insert :around (status)
    (if (or (eq this-command 'evil-collection-corfu-insert-exact)
            (not (eq status 'exact)))
        (cl-call-next-method)
      (evil-collection-corfu-unread-this-command-keys)
      (setq this-command 'evil-collection-corfu-insert-exact)))

  (mapc #'evil-declare-ignore-repeat
        '(corfu-next
          corfu-previous
          corfu-first
          corfu-last))

  (mapc #'evil-declare-change-repeat
        '(evil-collection-corfu-insert-exact
          corfu-insert
          corfu-complete)))

(provide 'evil-collection-corfu)
;;; evil-collection-corfu.el ends here
