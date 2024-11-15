@[translated]
module C:\Users\phcre\Documents\v\c2v\tests

struct ImVec2 { 
	x f32
	y f32
}
struct ImVec3 { 
	x f32
	y f32
	z f32
}
struct ImVec4 { 
	x f32
	y f32
	z f32
	w f32
}
struct ImGuiTextRange { 
	b &i8
	e &i8
}
struct ImVector_ImGuiTextRange { 
	size int
	capacity int
	data &ImGuiTextRange
}
type ImWchar16 = u16
struct ImGuiContext { 
	initialized int
}
