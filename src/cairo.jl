# GtkCanvas is the plain Gtk drawing canvas built on Cairo.
type GtkCanvas <: GtkWidget # NOT an @GType
    handle::Ptr{GtkObject}
    all::GdkRectangle
    mouse::MouseHandler
    resize::Union(Function,Nothing)
    draw::Union(Function,Nothing)
    back::CairoSurface   # backing store
    backcc::CairoContext

    function GtkCanvas(w, h)
        da = ccall((:gtk_drawing_area_new,libgtk),Ptr{GtkObject},())
        ccall((:gtk_widget_set_double_buffered,libgtk),Void,(Ptr{GtkObject},Int32), da, false)
        ccall((:gtk_widget_set_size_request,libgtk),Void,(Ptr{GtkObject},Int32,Int32), da, w, h)
        widget = new(da, GdkRectangle(0,0,w,h), MouseHandler(), nothing, nothing)
        widget.mouse.widget = widget
        on_signal_resize(notify_resize, widget)
        if gtk_version == 3
            signal_connect(canvas_on_draw_event,widget,"draw",Cint,(Ptr{Void},))
        else
            signal_connect(canvas_on_expose_event,widget,"expose-event",Void,(Ptr{Void},))
        end
        on_signal_button_press(mousedown_cb, widget, 0, widget.mouse)
        on_signal_button_release(mouseup_cb, widget, 0, widget.mouse)
        on_signal_motion(mousemove_cb, widget, 0, 0, 0, widget.mouse)
        gc_ref(widget)
    end
end
GtkCanvas() = GtkCanvas(-1,-1)

function notify_resize(::Ptr{GtkObject}, size::Ptr{GdkRectangle}, widget::GtkCanvas)
    widget.all = unsafe_load(size)
    widget.back = cairo_surface_for(widget)
    widget.backcc = CairoContext(widget.back)
    if isa(widget.resize,Function)
        widget.resize(widget)
    end
    draw(widget,false)
    nothing
end

function resize(config::Function, widget::GtkCanvas)
    widget.resize = config
    if widget.all.width > 0 && widget.all.height > 0
        if isa(widget.resize, Function)
            widget.resize(widget)
        end
        draw(widget, false)
    end
end

function draw(redraw::Function, widget::GtkCanvas)
    widget.draw = redraw
    draw(widget, false)
end

function draw(widget::GtkCanvas, immediate::Bool=true)
    if widget.all.width > 0 && widget.all.height > 0
        if isa(widget.draw,Function)
            widget.draw(widget)
        end
        reveal(widget, immediate)
    end
end

function cairo_surface_for(widget::GtkCanvas)
    w, h = width(widget), height(widget)
    CairoSurface(
        ccall((:gdk_window_create_similar_surface,libgdk), Ptr{Void},
        (Ptr{Void}, Enum, Int32, Int32), 
        gdk_window(widget), Cairo.CONTENT_COLOR_ALPHA, w, h),
    w, h)
end

function canvas_on_draw_event(::Ptr{GtkObject},cc::Ptr{Void},widget::GtkCanvas) # cc is a Cairo context
    ccall((:cairo_set_source_surface,Cairo._jl_libcairo), Void,
        (Ptr{Void},Ptr{Void},Float64,Float64), cc, widget.back.ptr, 0, 0)
    ccall((:cairo_paint,Cairo._jl_libcairo),Void, (Ptr{Void},), cc)
    int32(false) # propagate the event further
end

function canvas_on_expose_event(::Ptr{GtkObject},e::Ptr{Void},widget::GtkCanvas) # e is a GdkEventExpose
    cc = ccall((:gdk_cairo_create,libgdk),Ptr{Void},(Ptr{Void},),gdk_window(widget))
    ccall((:cairo_set_source_surface,Cairo._jl_libcairo), Void,
        (Ptr{Void},Ptr{Void},Float64,Float64), cc, widget.back.ptr, 0, 0)
    ccall((:cairo_paint,Cairo._jl_libcairo),Void, (Ptr{Void},), cc)
    ccall((:cairo_destroy,Cairo._jl_libcairo),Void, (Ptr{Void},), cc)
    nothing
end

getgc(c::GtkCanvas) = c.backcc
cairo_surface(c::GtkCanvas) = c.back

