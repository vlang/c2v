const int a = 0;

void f() 
{ 
    switch(a)
    {
    default:
    case 0:
    case 1:
        break;
    }

    switch(a)
    {
    default:
    case 0:
        break;
    }

    switch(a)
    {
    case 0:
        break;
    case 1:
        break;
    default:
    break;
    }
    
}