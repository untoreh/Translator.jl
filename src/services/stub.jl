srv_sym = :stub
srv_val = Val{srv_sym}
StubTR = Tuple{srv_val, TranslatorDict}

@typesderef function init(::Val{:stub}) end

@typesderef function init_translator(srv::srv_val; _...)
    (srv, TranslatorDict())
end

@typesderef function get_tfun(_::LangPair, _::StubTR)
    x -> x
end

push!(REG_SERVICES, srv_sym)
