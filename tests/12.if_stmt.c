int static inline quot( int x, int y ) {
	if( x == 0 || y == 0 )
		return	0;
	if( x > y )
		return	x%y ? 0 : x/y;
    else if (x == y)
        return	x%y ? 0 : x/y;
	else	
		return	y%x ? 0 : y/x;
}
int main() {
	quot(2,2);
}