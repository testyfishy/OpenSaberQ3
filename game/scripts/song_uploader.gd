extends Node
class_name SongUploader

# allows the player to upload a zip song file into the game songs folder, good for quest or web users

var server := TCPServer.new()
@export var PORT := 45800
const UPLOAD_DIR := Constants.APPDATA_PATH+"temp/"
const CRLF := "\r\n"

var active := false

# reference to the main main node (used for playing downloadable song previews)
@export var main_menu_ref: MainMenu

const STYLE := &"""@font-face {
	font-family: OpenSaber;
	src: url('/Roboto-Medium.ttf') format('truetype');
}
body {
	font-family: OpenSaber, Arial, sans-serif;
	background-color: #000;
	color: #ccc;
	max-width: 800px;
	margin: 0 auto;
	padding: 20px;
	border-style: solid;
	border-width: 5px;
	border-color: #ccc;
	text-align: center;
}
.upload-form {
	border-style: solid;
	border-width: 5px;
	border-color: #ccc;
	background-color: #0f0f0f;
	padding: 20px;
}
.title {
	padding: 10px;
}
input {
	font-family: OpenSaber, Arial, sans-serif;
	font-size: 1.17em;
}
input[type="submit"], input[type="file"]::file-selector-button {
	font-family: OpenSaber, Arial, sans-serif;
	border-style: solid;
	border-width: 5px;
	border-color: #ccc;
	background-color: #000;
	color: #ccc;
	padding: 5px;
}
input[type="submit"]:hover, input[type="file"]::file-selector-button:hover {
	background-color: #262626;
	color: #fff;
	border-color: #fff;
}
input[type="submit"]:active, input[type="file"]::file-selector-button:active {
	background-color: #454545;
	color: #fff;
	border-color: #fff;
}"""

func _enter_tree() -> void:
	if not DirAccess.dir_exists_absolute(UPLOAD_DIR):
		DirAccess.make_dir_recursive_absolute(UPLOAD_DIR)
	
	var err := server.listen(PORT)
	if err == OK:
		print("Server started on ", get_server_url())
		active = true
	else:
		print("Failed to start server: ", err)

func get_server_url() -> String:
	var ips := IP.get_local_addresses()
	var v4ips := []
	for i in range(ips.size()):
		if ips[i].count(".") == 3 and ips[i] != "127.0.0.1":
			v4ips.append(ips[i])
	if not v4ips.is_empty():
		return "http://%s:%s"%[v4ips[v4ips.size()-1], PORT]
	return "http://localhost:%s"%[ PORT]

func _process(_delta: float) -> void:
	if server.is_connection_available():
		var connection := server.take_connection()
		handle_connection(connection)

func handle_connection(connection: StreamPeerTCP) -> void:
	var request := PackedByteArray()
	
	# Read the headers first (until we find \r\n\r\n)
	var headers_complete := false
	var buffer := PackedByteArray()
	
	var pulls := 0
	while not headers_complete:
		if connection.get_available_bytes() > 0:
			buffer.append_array(connection.get_partial_data(1)[1])
			# Check for end of headers
			if buffer.size() >= 4:
				var last_four = buffer.slice(buffer.size() - 4)
				if last_four == "\r\n\r\n".to_utf8_buffer():
					headers_complete = true
		if pulls%64 == 0:
			await get_tree().process_frame
		pulls += 1
	
	request.append_array(buffer)
	var headers := request.get_string_from_utf8()
	
	if headers.begins_with("GET"):
		handle_get(connection, headers)
	elif headers.begins_with("POST"):
		await handle_post(connection, headers)
	else:
		send_error(connection, "405 Method Not Allowed")
	
	connection.disconnect_from_host()

func handle_get(connection: StreamPeerTCP, headers: String) -> void:
	var path := StringName(headers.substr(4, headers.find(" ", 4) - 4))
	match path:
		&"/Roboto-Medium.ttf":
			response_send_file(connection, "res://OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf")
		&"/favicon.ico":
			response_send_file(connection, "res://game/data/beepsaber_logo.png")
		_:
			response_show_uploader(connection)

func response_send_file(connection: StreamPeerTCP, path: String) -> void:
	var file := FileAccess.get_file_as_bytes(path)
	
	var headers := [
		"HTTP/1.1 200 OK",
		"Content-Type: text/html",
		"Content-Length: " + str(file.size()),
		"Connection: close"
	]
	
	var response := (CRLF.join(headers) + CRLF + CRLF).to_utf8_buffer() + file
	connection.put_data(response)

func response_show_uploader(connection: StreamPeerTCP) -> void:
	var response_body := """<!DOCTYPE html>
<html>
<head>
	<title>Open Saber Song Uploader</title>
	<style>""" + STYLE + """</style>
</head>
<body>
	<img src="/favicon.ico" />
	<h1 class="title">Open Saber Song Uploader</h1>
	<h3 class="title">Upload songs directly into the game's songs folder (must be a zip file)</h3>
	<div class="upload-form">
		<h3>Upload Song</h3>
		<form action="/" method="post" enctype="multipart/form-data" />
			<input type="file" name="file" accept=".zip, .ZIP" required />
			<br /><br />
			<input type="submit" value="Upload" />
		</form>
	</div>
</body>
</html>"""
	
	var headers := [
		"HTTP/1.1 200 OK",
		"Content-Type: text/html",
		"Content-Length: " + str(response_body.length()),
		"Connection: close"
	]
	
	var response := CRLF.join(headers) + CRLF + CRLF + response_body
	connection.put_data(response.to_utf8_buffer())

func find_byte_pattern(data: PackedByteArray, pattern: PackedByteArray, start: int = 0) -> int:
	if pattern.size() > data.size():
		return -1
	
	for i in range(start, data.size() - pattern.size() + 1):
		var found := true
		for j in range(pattern.size()):
			if data[i + j] != pattern[j]:
				found = false
				break
		if found:
			return i
	return -1



func handle_post(connection: StreamPeerTCP, headers: String) -> void:
	# Find the boundary in the Content-Type header
	var boundary_match := headers.find("boundary=")
	if boundary_match == -1:
		send_error(connection, "400 Bad Request")
		return
	
	var boundary := headers.substr(boundary_match + 9).split("\r\n")[0]
	var content_length_match := headers.find("Content-Length: ")
	
	if content_length_match == -1:
		send_error(connection, "400 Bad Request")
		return
	
	# Get Content-Length
	var content_length := int(headers.substr(content_length_match + 16).split("\r\n")[0])
	
	# Read the rest of the data
	var data := PackedByteArray()
	while data.size() < content_length and connection.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if connection.get_available_bytes() > 0:
			var chunk = connection.get_partial_data(1024)[1]
			data.append_array(chunk)
		await get_tree().process_frame
	
	var filename := "UploadedSong-%s"%[hash(data)]
	
	# Find the file content boundaries
	var content_start := find_byte_pattern(data, "\r\n\r\n".to_utf8_buffer(), 0) + 4
	if content_start == -1:
		send_error(connection, "400 Bad Request")
		return
	
	# Find the end boundary
	var boundary_end := "--" + boundary + "--"
	var content_end := find_byte_pattern(data, boundary_end.to_utf8_buffer(), content_start) - 2
	
	if content_end <= -1:
		send_error(connection, "400 Bad Request")
		return
	
	# Extract and save the file content
	var file_content := data.slice(content_start, content_end)
	var file := FileAccess.open(UPLOAD_DIR + filename + ".zip", FileAccess.WRITE)
	file.store_buffer(file_content)
	file.close()
	
	var unzipped_dir := unzip_song(filename)
	if unzipped_dir.is_empty() or DirAccess.get_files_at(unzipped_dir).is_empty():
		send_error(connection, "400 Unable to unzip file")
		return
	
	# Send success response
	var response_body := """<!DOCTYPE html>
<html>
<head>
	<title>Upload Success</title>
	<style>""" + STYLE + """</style>
</head>
<body>
	<h2>Song uploaded successfully!</h2>
	<h4>The song should appear on the songs list now</h4>
	<p>Folder Name: %s</p>
	<p>Size: %d bytes</p>
	<p><a href="/">Upload another song</a></p>
</body>
</html>""" % [filename, file_content.size()]

	var response_headers := [
		"HTTP/1.1 200 OK",
		"Content-Type: text/html",
		"Content-Length: " + str(response_body.length()),
		"Connection: close"
	]
	
	var response := CRLF.join(response_headers) + CRLF + CRLF + response_body
	connection.put_data(response.to_utf8_buffer())

func send_error(connection: StreamPeerTCP, error: String) -> void:
	var response_body := """
<!DOCTYPE html>
<html>
<head>
	<title>Error</title>
	<style>""" + STYLE + """</style>
</head>
<body>
	<h2>Error: %s</h2>
	<p><a href="/">Go back</a></p>
</body>
</html>""" % error

	var headers := [
		"HTTP/1.1 " + error,
		"Content-Type: text/html",
		"Content-Length: " + str(response_body.length()),
		"Connection: close"
	]
	
	var response := CRLF.join(headers) + CRLF + CRLF + response_body
	connection.put_data(response.to_utf8_buffer())

func _exit_tree() -> void:
	server.stop()

func unzip_song(filename := "") -> String:
	var zippath := UPLOAD_DIR + filename + ".zip"
	var song_out_dir := Constants.APPDATA_PATH + ("Songs/%s/"%filename)
	
	if DirAccess.make_dir_recursive_absolute(song_out_dir) != OK: 
		vr.log_error(
			"unzip_song - " +
			"Failed to create song output dir '%s'" % song_out_dir)
		return ""
	
	Utils.unzip(zippath,song_out_dir)
	
	DirAccess.remove_absolute(zippath)
	
	if main_menu_ref:
		main_menu_ref._on_LoadPlaylists_Button_pressed()
	
	return song_out_dir
