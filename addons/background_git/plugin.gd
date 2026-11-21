@tool
extends EditorPlugin
## Runs network work outside the editor, using the Windows Git credential manager.

const HELPER: String = "res://addons/background_git/push.ps1"
const MENU_NAME: String = "Push to GitHub (Background)"

var _button: Button
var _result_dialog: AcceptDialog
var _confirmation: ConfirmationDialog
var _pid: int = -1
var _result_path: String = ""
var _elapsed: float = 0.0


func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "Git Push"
	_button.tooltip_text = "Push committed changes in the background. Stage and commit in the Git panel first."
	_button.pressed.connect(_confirm_push)
	add_control_to_container(CONTAINER_TOOLBAR, _button)
	add_tool_menu_item(MENU_NAME, _confirm_push)
	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "Background Git Push"
	_result_dialog.dialog_autowrap = true
	add_child(_result_dialog)
	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "Push committed changes"
	_confirmation.dialog_text = "Push this branch's commits to origin?\n\nUncommitted files are not included. Stage and commit them in the Git panel first.\nThe editor stays available while the push runs."
	_confirmation.ok_button_text = "Push commits"
	_confirmation.confirmed.connect(_start_push)
	add_child(_confirmation)
	set_process(false)
	if OS.get_name() != "Windows":
		_button.disabled = true
		_button.tooltip_text = "This helper currently supports Windows."


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	remove_control_from_container(CONTAINER_TOOLBAR, _button)
	_button.queue_free()
	_result_dialog.queue_free()
	_confirmation.queue_free()
	# The independent helper can finish even if the editor closes; it has its own timeout.


func _process(delta: float) -> void:
	if _pid <= 0:
		set_process(false)
		return
	_elapsed += delta
	_button.text = "Pushing… %ds" % int(_elapsed)
	if OS.is_process_running(_pid):
		return
	set_process(false)
	_pid = -1
	_button.disabled = false
	_button.text = "Git Push"
	if not FileAccess.file_exists(_result_path):
		_show_result("Push helper stopped without a result. Check that Windows PowerShell and Git are installed.")
		return
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_result_path)) != OK or not parser.data is Dictionary:
		_show_result("Could not read the push result: " + _result_path)
		return
	var result: Dictionary = parser.data
	_show_result(str(result.get("message", "Unknown push result.")))


func _confirm_push() -> void:
	if _pid > 0 or OS.get_name() != "Windows":
		return
	_confirmation.popup_centered(Vector2i(620, 220))


func _start_push() -> void:
	if _pid > 0:
		return
	var result_dir: String = ProjectSettings.globalize_path("res://.godot/background_git")
	if DirAccess.make_dir_recursive_absolute(result_dir) != OK:
		_show_result("Could not create the background push log folder.")
		return
	_result_path = result_dir.path_join("result-%d.json" % Time.get_ticks_usec())
	var powershell: String = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var args: PackedStringArray = PackedStringArray([
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
		ProjectSettings.globalize_path(HELPER),
		"-Repository", ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"-ResultPath", _result_path,
	])
	_pid = OS.create_process(powershell, args, false)
	if _pid <= 0:
		_show_result("Could not start Windows PowerShell for the background push.")
		return
	_elapsed = 0.0
	_button.disabled = true
	_button.text = "Pushing…"
	set_process(true)


func _show_result(message: String) -> void:
	print("Background Git: ", message)
	_result_dialog.dialog_text = message.left(6000)
	_result_dialog.popup_centered(Vector2i(720, 360))
