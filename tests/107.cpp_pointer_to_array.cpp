struct Vertex {
	float x;
};

float read_vertex(Vertex (*rows)[3], int row, int column) {
	return rows[row][column].x;
}

float read_parenthesized_pointer(const Vertex (*vertices), int index) {
	return vertices[index].x;
}
