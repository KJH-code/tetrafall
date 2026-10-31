# 내보내기 플러그인 등록 (편집기·헤드리스 내보내기 때만)
@tool
extends EditorPlugin

const Export := preload("res://addons/web_music/export.gd")
var _ex: EditorExportPlugin


func _enter_tree() -> void:
	_ex = Export.new()
	add_export_plugin(_ex)


func _exit_tree() -> void:
	remove_export_plugin(_ex)
	_ex = null
