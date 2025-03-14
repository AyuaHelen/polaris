#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>
#include <readline/rlstdc.h>

#include <caml/alloc.h>
#include <caml/mlvalues.h>

char* readline_default_buffer = NULL;

int getc_wrapper(FILE* file){
    if (readline_default_buffer != NULL){
        // If we reached the end of the buffer, set its pointer to 0
        // and defer to getc.
        // The buffer is *NOT* freed!
        if (*readline_default_buffer == '\0'){
            readline_default_buffer = NULL;
            return getc(file);
        } 
        // Otherwise, read the first character and advance the buffer
        else {
            int result = *readline_default_buffer;
            readline_default_buffer++;
            return result;
        }
    } 
    // If the default buffer is not used, defer to gcc
    else {
        return getc(file);
    }
}

CAMLprim value readline_stub(value prompt) {
    using_history();

    rl_getc_function = getc_wrapper;

    char* result_str = readline(String_val(prompt));

    if (result_str == NULL){
        return Val_none;
    } else {
        add_history(result_str);
        value result = caml_copy_string(result_str);
        free(result_str);
        return caml_alloc_some(result);
    }
}

CAMLprim value readline_default_stub(value prompt, value default_value) {
    readline_default_buffer = String_val(default_value);
    return readline_stub(prompt);
}
