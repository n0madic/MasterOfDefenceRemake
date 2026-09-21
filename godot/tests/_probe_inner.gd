extends RefCounted
func run(root: Window) -> void:
	var view := LocationView.new()
	print("before add: conn=", Ticker.ticked.is_connected(view._on_ticked), " ticker_inside=", Ticker.is_inside_tree())
	root.add_child(view)
	print("after add: inside=", view.is_inside_tree(), " conn=", Ticker.ticked.is_connected(view._on_ticked), " root_ready=", root.is_node_ready(), " ready=", view.is_node_ready())
	print("root children: ", root.get_children())
	root.remove_child(view)
	view.free()
