// gcc -c image_funcs.c -o image_funcs.o -I include/

#include <stdio.h>
#include <stdlib.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"

#pragma pack(1)
struct image_data
{
    char filename[255];
    unsigned int width;
    unsigned int height;
    long long pixel_data;
};
#pragma pack()

unsigned char* load_image(const char* filename, int* w, int* h)
{
    int end_width = *w, end_height = *h;

    // Make sure that the data will be right side up
    stbi_set_flip_vertically_on_load(1);

    // Load the image data
    int c;
    unsigned char* data = stbi_load(filename, w, h, &c, 0);

    // Check if there was an error with loading the image data
    if (data == NULL) 
    {
        fprintf(stderr, "Error: Failed to load image %s\n", filename);
        return NULL;
    }

    // Make sure that there are 4 channels (rgba)
    if (c == 3)
    {       
        unsigned char* rgba_data = malloc(*w * *h * 4);

        for (int i = 0; i < *w * *h; i++)
        {
            rgba_data[i * 4] = data[i * 3];      
            rgba_data[i * 4 + 1] = data[i * 3 + 1];
            rgba_data[i * 4 + 2] = data[i * 3 + 2];
            rgba_data[i * 4 + 3] = 255;
        }

        data = rgba_data;
    }

    // Resize the image if needed
    if (end_width != 0 && end_height != 0)
    {
        unsigned char* resized_data = malloc(end_width * end_height * 4);
        stbir_resize_uint8(data, *w, *h, 0, resized_data, end_width, end_height, 0, 4);
        data = resized_data;
    }

    // Return the image data
    return data;
}

void load_image_data(struct image_data* data_ptr)
{
    unsigned char* pixel_data = load_image(data_ptr->filename, &data_ptr->width, &data_ptr->height);
    data_ptr->pixel_data = (long long)pixel_data;
    return;
}

void load_scaled_image_data(struct image_data* data_ptr, int width, int height)
{
    data_ptr->width = width;
    data_ptr->height = height;

    unsigned char* pixel_data = load_image(data_ptr->filename, &data_ptr->width, &data_ptr->height);

    data_ptr->pixel_data = (long long)pixel_data;
    data_ptr->width = width;
    data_ptr->height = height;

    return;
}


