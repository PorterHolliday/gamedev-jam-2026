extends Control

@onready var rich_text_label: RichTextLabel = %RichTextLabel

func _ready() -> void:
	rich_text_label.meta_clicked.connect(_on_richtextlabel_meta_clicked)

func _on_richtextlabel_meta_clicked(meta) -> void:
	if OS.has_feature('web'):
		JavaScriptBridge.eval("window.open('"+str(meta)+"', '_blank').focus();")
	else:
		OS.shell_open(str(meta))
